defmodule IM.Conversation.UnreadCache do
  @moduledoc """
  未读数热路径：Redis/Memory INCR，PG `conversations.unread_count` 异步刷库。

  键：
  - `im:unread:{app_key}:{user_id}:{conv_id}` — pending 增量
  - `im:unread:dirty:{app_key}` — 待刷库 `{user_id}:{conv_id}` SET
  """

  alias IM.Cache

  @doc "收件人未读 +1。"
  @spec incr(String.t(), String.t(), String.t()) :: :ok
  def incr(app_key, user_id, conv_id)
      when is_binary(app_key) and is_binary(user_id) and is_binary(conv_id) do
    _ = Cache.incr(unread_key(app_key, user_id, conv_id))
    _ = Cache.sadd(dirty_key(app_key), dirty_member(user_id, conv_id))
    :ok
  end

  @doc "Redis 中尚未合并到 PG 的 pending 增量。"
  @spec pending(String.t(), String.t(), String.t()) :: non_neg_integer()
  def pending(app_key, user_id, conv_id)
      when is_binary(app_key) and is_binary(user_id) and is_binary(conv_id) do
    case Cache.get(unread_key(app_key, user_id, conv_id)) do
      {:ok, val} when is_binary(val) and val != "" ->
        case Integer.parse(val) do
          {n, _} when n > 0 -> n
          _ -> 0
        end

      _ ->
        0
    end
  end

  @doc "已读或刷库后删除 pending 键。"
  @spec reset(String.t(), String.t(), String.t()) :: :ok
  def reset(app_key, user_id, conv_id)
      when is_binary(app_key) and is_binary(user_id) and is_binary(conv_id) do
    _ = Cache.del(unread_key(app_key, user_id, conv_id))
    _ = Cache.srem(dirty_key(app_key), dirty_member(user_id, conv_id))
    :ok
  end

  @doc "列出待刷库的 `{user_id, conv_id}`（最多 `limit` 条）。"
  @spec list_dirty(String.t(), pos_integer()) :: [{String.t(), String.t()}]
  def list_dirty(app_key, limit) when is_binary(app_key) and is_integer(limit) and limit > 0 do
    case Cache.smembers(dirty_key(app_key)) do
      {:ok, members} ->
        members
        |> Enum.take(limit)
        |> Enum.map(&parse_dirty_member/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp parse_dirty_member(member) when is_binary(member) do
    case String.split(member, ":", parts: 2) do
      [user_id, conv_id] when user_id != "" and conv_id != "" -> {user_id, conv_id}
      _ -> nil
    end
  end

  defp parse_dirty_member(_), do: nil

  defp unread_key(app_key, user_id, conv_id),
    do: "im:unread:#{app_key}:#{user_id}:#{conv_id}"

  defp dirty_key(app_key), do: "im:unread:dirty:#{app_key}"
  defp dirty_member(user_id, conv_id), do: "#{user_id}:#{conv_id}"
end
