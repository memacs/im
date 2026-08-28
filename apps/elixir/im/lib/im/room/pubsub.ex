defmodule IM.Room.PubSub do
  @moduledoc "聊天室 PubSub topic 与广播。"

  @doc """
  Topic：`room:{app_key}:{room_id}`。
  """
  @spec topic(String.t(), String.t()) :: String.t()
  def topic(app_key, room_id), do: "room:#{app_key}:#{room_id}"

  @doc """
  当前进程订阅聊天室。
  """
  @spec subscribe(String.t(), String.t()) :: :ok
  def subscribe(app_key, room_id) do
    :ok = Phoenix.PubSub.subscribe(IM.PubSub, topic(app_key, room_id))
  end

  @doc """
  取消订阅。
  """
  @spec unsubscribe(String.t(), String.t()) :: :ok
  def unsubscribe(app_key, room_id) do
    :ok = Phoenix.PubSub.unsubscribe(IM.PubSub, topic(app_key, room_id))
  end

  @doc """
  广播已编码 Packet（含投递过滤元数据）。
  """
  @spec broadcast(String.t(), String.t(), binary(), map()) :: :ok
  def broadcast(app_key, room_id, packet_binary, meta) when is_binary(packet_binary) do
    Phoenix.PubSub.broadcast(
      IM.PubSub,
      topic(app_key, room_id),
      {:im_room_push, packet_binary, meta}
    )
  end
end
