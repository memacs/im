defmodule IM.Message.ClientMsgIdCache do
  @moduledoc """
  发送幂等键热缓存：`client_msg_id` → `msg_id`（PG 仍为权威）。

  键：`im:cmid:{app}:{from}:{client_msg_id}`。
  """

  alias IM.Cache

  @default_ttl_sec 72 * 3600

  @doc "查找已分配的 msg_id；未命中返回 `:miss`。"
  @spec lookup(String.t(), String.t(), String.t()) :: {:ok, String.t()} | :miss
  def lookup(app_key, from_uid, client_msg_id)
      when is_binary(app_key) and is_binary(from_uid) and is_binary(client_msg_id) do
    case Cache.get(key(app_key, from_uid, client_msg_id)) do
      {:ok, msg_id} when is_binary(msg_id) and msg_id != "" -> {:ok, msg_id}
      _ -> :miss
    end
  end

  @doc "写穿 msg_id（成功落库后调用）。"
  @spec put(String.t(), String.t(), String.t(), String.t()) :: :ok
  def put(app_key, from_uid, client_msg_id, msg_id)
      when is_binary(app_key) and is_binary(from_uid) and is_binary(client_msg_id) and
             is_binary(msg_id) do
    ttl = Application.get_env(:im, :client_msg_id_cache_ttl_sec, @default_ttl_sec)
    _ = Cache.set_ex(key(app_key, from_uid, client_msg_id), msg_id, ttl)
    :ok
  end

  defp key(app_key, from_uid, client_msg_id),
    do: "im:cmid:#{app_key}:#{from_uid}:#{client_msg_id}"
end
