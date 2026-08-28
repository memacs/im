defmodule IM.ClusterPeer do
  @moduledoc false

  alias IM.UserTracker

  @doc "是否启用集群 E2E（`CLUSTER_E2E=1`）。"
  @spec enabled?() :: boolean()
  def enabled?, do: System.get_env("CLUSTER_E2E") == "1"

  @doc "peer 节点 HTTP 基址。"
  @spec base_url() :: String.t()
  def base_url do
    "http://127.0.0.1:#{peer_port()}"
  end

  @doc "peer 节点 WebSocket 地址。"
  @spec ws_url() :: String.t()
  def ws_url, do: base_url() <> "/ws"

  @doc "本机（主测）节点名。"
  @spec main_node() :: node()
  def main_node, do: persistent!(:main)

  @doc "peer 节点名。"
  @spec peer_node() :: node()
  def peer_node, do: persistent!(:peer)

  @doc "启动分布式主节点 + peer IM 节点（主节点须已 `start_owner!(..., sandbox: false)`）。"
  @spec start_cluster!(pid()) :: :ok
  def start_cluster!(_main_owner) do
    case :persistent_term.get({__MODULE__, :started}, false) do
      true ->
        :ok

      false ->
        main = ensure_distributed!()
        {:ok, peer_pid, peer} = start_peer!(main)

        :persistent_term.put({__MODULE__, :main}, main)
        :persistent_term.put({__MODULE__, :peer}, peer)
        :persistent_term.put({__MODULE__, :peer_pid}, peer_pid)
        :persistent_term.put({__MODULE__, :started}, true)

        nodes = Enum.sort([main, peer])
        Application.put_env(:im, :message_nodes, nodes)

        true = Node.connect(peer)
        wait_connected!(main, peer)
        setup_peer_sandbox!(peer)
        :ok
    end
  end

  @doc "停止 peer 节点。"
  @spec stop_cluster!() :: :ok
  def stop_cluster! do
    case persistent_term(:peer_pid, nil) do
      pid when is_pid(pid) ->
        try do
          :peer.stop(pid)
        catch
          :exit, _ -> :ok
        end

      _ ->
        :ok
    end

    restore_main_env()
    :persistent_term.erase({__MODULE__, :started})
    :persistent_term.erase({__MODULE__, :peer_owner})
    :ok
  end

  @doc "停止 peer 节点。"
  @spec route_key_for_node(node()) :: String.t()
  def route_key_for_node(target_node) do
    1..10_000
    |> Enum.find(fn i ->
      key = "cluster-rk-#{i}"
      IM.Cluster.Router.owner(key) == target_node
    end)
    |> case do
      nil -> flunk("no route_key maps to #{inspect(target_node)}")
      i -> "cluster-rk-#{i}"
    end
  end

  @doc "等待 UserTracker 在集群内可见某设备。"
  @spec wait_device_tracked!(String.t(), String.t(), String.t(), node()) :: :ok
  def wait_device_tracked!(app_key, user_id, device_id, on_node) do
    unless wait_until(fn ->
             UserTracker.list_devices(app_key, user_id)
             |> Enum.any?(&(&1.device_id == device_id and &1.node == on_node))
           end) do
      flunk("device #{device_id} not tracked on #{inspect(on_node)}")
    end

    :ok
  end

  defp setup_peer_sandbox!(peer) do
    owner = :rpc.call(peer, IM.ClusterPeerBoot, :start_sandbox_owner!, [])

    unless is_pid(owner) do
      flunk("peer sandbox owner failed: #{inspect(owner)}")
    end

    :persistent_term.put({__MODULE__, :peer_owner}, owner)
    :ok
  end

  defp ensure_distributed! do
    case Node.self() do
      :nonode@nohost ->
        name = :"im_test@127.0.0.1"
        {:ok, _} = :net_kernel.start([name, :longnames])
        name

      name ->
        name
    end
  end

  defp cluster_cookie do
    Node.get_cookie()
  end

  defp start_peer!(main_node) do
    port = peer_port()

    {:ok, pid, peer_node} =
      :peer.start_link(%{
        name: :im_peer,
        cookie: cluster_cookie(),
        host: ~c"127.0.0.1"
      })

    unless wait_until(fn -> peer_node in Node.list() end) do
      flunk("peer node #{inspect(peer_node)} not connected")
    end

    :ok = :rpc.call(peer_node, :code, :add_paths, [:code.get_path()])

    case :rpc.call(
           peer_node,
           IM.ClusterPeerBoot,
           :boot,
           [
             main_node,
             peer_node,
             port,
             Application.fetch_env!(:im, IM.Repo)
           ],
           120_000
         ) do
      :ok -> {:ok, pid, peer_node}
      other -> flunk("peer boot failed: #{inspect(other)}")
    end
  end

  defp peer_port do
    partition = String.to_integer(System.get_env("MIX_TEST_PARTITION") || "0")
    4102 + partition
  end

  defp wait_connected!(a, b) do
    unless wait_until(fn -> b in Node.list() and a in :rpc.call(b, Node, :list, []) end) do
      flunk("cluster nodes not connected: #{inspect(a)} <-> #{inspect(b)}")
    end
  end

  defp wait_until(fun, attempts \\ 50) do
    cond do
      fun.() ->
        true

      attempts <= 0 ->
        false

      true ->
        Process.sleep(50)
        wait_until(fun, attempts - 1)
    end
  end

  defp persistent!(key) do
    :persistent_term.get({__MODULE__, key})
  end

  defp persistent_term(key, default) do
    :persistent_term.get({__MODULE__, key}, default)
  end

  defp restore_main_env do
    Application.delete_env(:im, :message_nodes)
  end

  defp flunk(msg), do: raise(ExUnit.AssertionError, msg: msg)
end
