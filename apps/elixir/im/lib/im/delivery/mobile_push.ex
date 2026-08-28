defmodule IM.Delivery.MobilePush do
  @moduledoc """
  移动推送入队（P5-09 进程内队列 + P9-03c EventBus `im.push` 旁路）。
  """

  use GenServer

  alias IM.EventBus.Push, as: EventPush
  alias IM.Stores.UserDeviceStore

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  若用户无在线连接且有 push_token，则入队；并旁路写 `im.push`。

  ## 示例

      IM.Delivery.MobilePush.maybe_enqueue("a", "u", bin, online?: false, msg_id: "m1")
  """
  @spec maybe_enqueue(String.t(), String.t(), binary(), keyword()) :: :ok
  def maybe_enqueue(app_key, user_id, packet_binary, opts \\ [])
      when is_binary(app_key) and is_binary(user_id) and is_binary(packet_binary) do
    online? = Keyword.get(opts, :online?, false)

    unless online? do
      devices = UserDeviceStore.list_with_push_token(app_key, user_id)

      targets =
        Enum.map(devices, fn d ->
          item = %{
            app_key: app_key,
            user_id: user_id,
            device_id: d.device_id,
            push_token: d.push_token,
            platform: d.platform,
            payload: packet_binary
          }

          GenServer.cast(__MODULE__, {:enqueue, item})
          item
        end)

      if targets != [] do
        msg_id = Keyword.get(opts, :msg_id) || "unknown"

        _ =
          EventPush.publish_batch(msg_id, targets,
            app_key: app_key,
            conv_id: Keyword.get(opts, :conv_id)
          )
      end
    end

    :ok
  end

  @doc """
  测试用：弹出队列项。
  """
  @spec drain() :: [map()]
  def drain do
    GenServer.call(__MODULE__, :drain)
  end

  @impl true
  def init(_opts), do: {:ok, %{queue: :queue.new(), size: 0}}

  @impl true
  def handle_cast({:enqueue, item}, state) do
    :telemetry.execute([:im, :mobile_push, :enqueue], %{count: 1}, %{platform: item.platform})
    {:noreply, %{state | queue: :queue.in(item, state.queue), size: state.size + 1}}
  end

  @impl true
  def handle_call(:drain, _from, state) do
    items = :queue.to_list(state.queue)
    {:reply, items, %{queue: :queue.new(), size: 0}}
  end
end
