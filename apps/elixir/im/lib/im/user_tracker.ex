defmodule IM.UserTracker do
  @moduledoc """
  基于 `Phoenix.Tracker` 的用户设备在线定位（P5-03）。

  topic = `user:{app_key}:{user_id}`，key = `device_id`。
  集群内 CRDT 同步后，可用远程 pid 直接 `send/2`（需已形成 Erlang 集群）。
  """

  use Phoenix.Tracker

  @doc false
  def start_link(opts \\ []) do
    opts =
      Keyword.merge(
        [
          name: __MODULE__,
          pubsub_server: IM.PubSub,
          broadcast_period: 500,
          max_silent_periods: 10,
          pool_size: 1
        ],
        opts
      )

    Phoenix.Tracker.start_link(__MODULE__, opts, opts)
  end

  @impl true
  def init(opts) do
    server = Keyword.fetch!(opts, :pubsub_server)
    {:ok, %{pubsub_server: server}}
  end

  @impl true
  def handle_diff(_diff, state), do: {:ok, state}

  @doc """
  将当前进程登记为用户某设备在线。

  ## 示例

      IM.UserTracker.track("a", "u", "d1", %{platform: "ios"})
  """
  @spec track(String.t(), String.t(), String.t(), map()) :: :ok | {:error, term()}
  def track(app_key, user_id, device_id, meta \\ %{})
      when is_binary(app_key) and is_binary(user_id) and is_binary(device_id) do
    meta =
      meta
      |> Map.put(:device_id, device_id)
      |> Map.put_new(:platform, "unknown")
      |> Map.put(:node, node())
      |> Map.put_new(:connected_at, System.system_time(:millisecond))

    case Phoenix.Tracker.track(__MODULE__, self(), topic(app_key, user_id), device_id, meta) do
      {:ok, _ref} -> :ok
      {:error, {:already_tracked, _, _, _}} -> :ok
      {:error, _} = err -> err
    end
  end

  @doc """
  列出用户在线设备：`[%{pid, device_id, platform, node}]`。

  ## 示例

      IM.UserTracker.list_devices("a", "u")
  """
  @spec list_devices(String.t(), String.t()) :: [map()]
  def list_devices(app_key, user_id) do
    t = topic(app_key, user_id)

    Phoenix.Tracker.list(__MODULE__, t)
    |> Enum.flat_map(fn {device_id, _meta} ->
      Phoenix.Tracker.get_by_key(__MODULE__, t, device_id)
      |> Enum.map(fn {pid, meta} ->
        %{
          pid: pid,
          device_id: device_id,
          platform: Map.get(meta, :platform) || Map.get(meta, "platform"),
          node: Map.get(meta, :node) || Map.get(meta, "node") || node(pid)
        }
      end)
    end)
  end

  defp topic(app_key, user_id), do: "user:#{app_key}:#{user_id}"
end
