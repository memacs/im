defmodule IM.Cluster.GroupPusher do
  @moduledoc """
  大群树状扇出（design/group.md §5.1）。

  预编码 `packet_binary` 全树共享；按 BEAM node 分组后树状 RPC / 本地并行写出。
  """

  require IM.Log

  alias IM.Cluster.{FanoutBatcher, SlowNode}
  alias IM.Delivery.MobilePush
  alias IM.Group.{FanoutConfig, FanoutPolicy}
  alias IM.UserTracker

  @doc """
  向群收件人推送已编码 Packet。

  Options:
  - `:exclude` — `%{user_id => device_id}` 排除设备
  - `:force_tree` — 强制走树状路径（测试用）

  ## 示例

      IM.Cluster.GroupPusher.push("app", ["u1", "u2"], bin, exclude: %{"u1" => "d1"})
  """
  @spec push(String.t(), [String.t()], binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def push(app_key, user_ids, packet_binary, opts \\ [])
      when is_binary(app_key) and is_list(user_ids) and is_binary(packet_binary) do
    start = System.monotonic_time()
    exclude = Keyword.get(opts, :exclude, %{})
    force_tree? = Keyword.get(opts, :force_tree, false)

    by_node = collect_by_node(app_key, user_ids, exclude)

    online_users =
      by_node |> Map.values() |> List.flatten() |> Enum.map(& &1.user_id) |> Enum.uniq()

    online_set = MapSet.new(online_users)
    nodes = Map.keys(by_node) |> Enum.reject(&SlowNode.isolated?/1)

    use_tree? =
      force_tree? or FanoutPolicy.use_tree_push?(length(online_users)) or
        length(nodes) > FanoutConfig.get(:branching_factor)

    result =
      if use_tree? do
        tree_push(by_node, packet_binary)
      else
        direct_push(by_node, packet_binary)
      end

    # P5-09：离线且有 push_token → 移动推送队列
    push_opts = [
      msg_id: Keyword.get(opts, :msg_id),
      conv_id: Keyword.get(opts, :conv_id)
    ]

    Enum.each(user_ids, fn uid ->
      unless MapSet.member?(online_set, uid) do
        MobilePush.maybe_enqueue(
          app_key,
          uid,
          packet_binary,
          Keyword.merge(push_opts, online?: false)
        )
      end
    end)

    duration = System.monotonic_time() - start

    :telemetry.execute(
      [:im, :group, :tree_fanout],
      %{duration: duration, nodes: length(nodes), depth: result.depth, miss: result.miss},
      %{tree: use_tree?}
    )

    {:ok, Map.put(result, :tree?, use_tree?)}
  end

  @doc false
  # 供 :erpc 远程调用
  def local_deliver(targets, packet_binary) when is_list(targets) and is_binary(packet_binary) do
    t0 = System.monotonic_time(:millisecond)
    pids = Enum.map(targets, & &1.pid) |> Enum.uniq()
    :ok = FanoutBatcher.deliver_encoded(pids, packet_binary)
    elapsed = System.monotonic_time(:millisecond) - t0

    if elapsed > FanoutConfig.get(:slow_node_ms) do
      SlowNode.mark(node(), FanoutConfig.get(:slow_isolate_sec))
    end

    {:ok, length(pids)}
  end

  defp collect_by_node(app_key, user_ids, exclude) do
    user_ids
    |> Enum.flat_map(fn uid ->
      excl = Map.get(exclude, uid)

      UserTracker.list_devices(app_key, uid)
      |> Enum.reject(fn d -> excl && d.device_id == excl end)
      |> Enum.map(fn d ->
        %{
          user_id: uid,
          pid: d.pid,
          device_id: d.device_id,
          node: d.node || node(d.pid)
        }
      end)
    end)
    |> Enum.group_by(& &1.node)
  end

  defp direct_push(by_node, packet_binary) do
    miss =
      Enum.reduce(by_node, 0, fn {n, targets}, acc ->
        case rpc_deliver(n, targets, packet_binary) do
          {:ok, _} -> acc
          _ -> acc + length(targets)
        end
      end)

    %{depth: 1, miss: miss}
  end

  defp tree_push(by_node, packet_binary) do
    nodes = Map.keys(by_node) |> Enum.reject(&SlowNode.isolated?/1) |> Enum.sort()
    branching = FanoutConfig.get(:branching_factor)
    parallelism = FanoutConfig.get(:coordinator_parallelism)
    timeout = FanoutConfig.get(:rpc_timeout_ms)

    {depth, miss} =
      fanout_nodes(nodes, by_node, packet_binary, branching, parallelism, timeout, 1)

    %{depth: depth, miss: miss}
  end

  defp fanout_nodes([], _by_node, _bin, _branching, _par, _timeout, depth), do: {depth, 0}

  defp fanout_nodes(nodes, by_node, bin, branching, par, timeout, depth) do
    max_depth = FanoutConfig.get(:max_depth)

    if length(nodes) <= branching or depth >= max_depth do
      miss =
        nodes
        |> Task.async_stream(
          fn n -> rpc_deliver(n, Map.get(by_node, n, []), bin) end,
          max_concurrency: par,
          timeout: timeout + 100,
          on_timeout: :kill_task
        )
        |> Enum.reduce(0, fn
          {:ok, {:ok, _}}, acc -> acc
          {:ok, _}, acc -> acc + 1
          {:exit, _}, acc -> acc + 1
        end)

      {depth, miss}
    else
      chunks = Enum.chunk_every(nodes, branching)
      # 每块选首节点为中继：中继负责其 chunk 内全部节点
      miss =
        chunks
        |> Task.async_stream(
          fn chunk ->
            relay = hd(chunk)
            subset = Map.take(by_node, chunk)
            relay_push(relay, subset, bin, timeout)
          end,
          max_concurrency: par,
          timeout: timeout * 2,
          on_timeout: :kill_task
        )
        |> Enum.reduce(0, fn
          {:ok, n}, acc when is_integer(n) -> acc + n
          {:ok, _}, acc -> acc
          {:exit, _}, acc -> acc + 1
        end)

      {depth + 1, miss}
    end
  end

  defp relay_push(relay, subset_by_node, bin, timeout) do
    if relay == node() do
      # 本地中继：继续对 subset 做一层直推
      direct_push(subset_by_node, bin).miss
    else
      case :erpc.call(relay, __MODULE__, :relay_subset, [subset_by_node, bin], timeout) do
        {:ok, miss} -> miss
        _ -> map_size(subset_by_node)
      end
    end
  rescue
    _ -> map_size(subset_by_node)
  end

  @doc false
  def relay_subset(subset_by_node, bin) when is_map(subset_by_node) do
    {:ok, direct_push(subset_by_node, bin).miss}
  end

  defp rpc_deliver(n, targets, bin) when n == node() or n == :nonode@nohost do
    local_deliver(targets, bin)
  end

  defp rpc_deliver(n, targets, bin) do
    IM.Telemetry.Cluster.dispatch(1)
    timeout = FanoutConfig.get(:rpc_timeout_ms)
    retries = FanoutConfig.get(:retry_max)

    do_rpc(n, targets, bin, timeout, retries)
  end

  defp do_rpc(_n, _targets, _bin, _timeout, retries) when retries < 0 do
    IM.Log.error(:cluster_dispatch_failed, reason: "rpc_timeout")
    {:error, :timeout}
  end

  defp do_rpc(n, targets, bin, timeout, retries) do
    case :erpc.call(n, __MODULE__, :local_deliver, [targets, bin], timeout) do
      {:ok, _} = ok ->
        ok

      _ ->
        do_rpc(n, targets, bin, timeout, retries - 1)
    end
  rescue
    _ -> do_rpc(n, targets, bin, timeout, retries - 1)
  end
end
