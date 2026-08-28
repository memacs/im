defmodule IM.Services.Offline do
  @moduledoc "离线拉取（Phase 4/5：含读扩散 conv_seq 直查）。"

  alias IM.Domain.{Error, MessageContext}
  alias IM.Group.FanoutPolicy
  alias IM.Stores.MessageStore
  alias Pb.Im.Protocol.{ChatMessage, MsgType, OfflinePullReq, OfflinePullResp}

  @default_limit 50
  @max_limit 200

  @doc """
  执行离线拉取。

  ## 示例

      IM.Services.Offline.pull(req, ctx)
  """
  @spec pull(OfflinePullReq.t(), MessageContext.t()) ::
          {:ok, OfflinePullResp.t()} | {:error, Error.t()}
  def pull(%OfflinePullReq{} = req, %MessageContext{} = ctx) do
    limit = clamp_limit(req.limit)
    after_seq = max(req.cursor || 0, 0)
    conv_scoped? = req.conv_id not in [nil, ""]

    rows =
      cond do
        conv_scoped? and read_fanout_conv?(ctx.app_key, req.conv_id) ->
          MessageStore.list_bodies_by_conv_seq(
            ctx.app_key,
            req.conv_id,
            after_seq,
            limit + 1,
            ctx.user_id
          )

        conv_scoped? ->
          inbox_rows =
            MessageStore.list_by_conv_seq(
              ctx.app_key,
              ctx.user_id,
              req.conv_id,
              after_seq,
              limit + 1
            )

          # 写扩散缺行时 fallback 直查 bodies（异步 inbox 窗口）
          if inbox_rows == [] do
            MessageStore.list_bodies_by_conv_seq(
              ctx.app_key,
              req.conv_id,
              after_seq,
              limit + 1,
              ctx.user_id
            )
          else
            inbox_rows
          end

        true ->
          MessageStore.list_by_inbox_seq(ctx.app_key, ctx.user_id, after_seq, limit + 1)
      end

    has_more = length(rows) > limit
    page = Enum.take(rows, limit)

    messages =
      Enum.map(page, fn %{body: b, inbox_seq: inbox_seq} ->
        %ChatMessage{
          msg_id: b.msg_id,
          client_msg_id: b.client_msg_id || "",
          chat_type: chat_type_atom(b.chat_type),
          from: b.from_uid,
          to: b.to_id,
          conv_id: b.conv_id,
          msg_type: msg_type_atom(b.msg_type),
          content: b.content,
          server_time: b.server_time,
          conv_seq: b.conv_seq,
          inbox_seq: inbox_seq
        }
      end)

    next_cursor =
      case List.last(page) do
        nil ->
          after_seq

        %{body: %{conv_seq: conv_seq}, inbox_seq: inbox_seq} ->
          if conv_scoped?, do: conv_seq, else: inbox_seq
      end

    {:ok,
     %OfflinePullResp{
       messages: messages,
       has_more: has_more,
       next_cursor: next_cursor
     }}
  end

  defp read_fanout_conv?(app_key, "g:" <> group_id) do
    case IM.Group.MetaCache.get(app_key, group_id) do
      {:ok, group} -> FanoutPolicy.storage_mode(group) == :read_fanout
      _ -> false
    end
  end

  defp read_fanout_conv?(_, _), do: false

  defp chat_type_atom(1), do: :CHAT_PRIVATE
  defp chat_type_atom(2), do: :CHAT_GROUP
  defp chat_type_atom(3), do: :CHAT_ROOM
  defp chat_type_atom(_), do: :CHAT_PRIVATE

  defp msg_type_atom(n) when is_integer(n) do
    case MsgType.key(n) do
      atom when is_atom(atom) -> atom
      _ -> :MSG_TEXT
    end
  end

  defp msg_type_atom(atom) when is_atom(atom), do: atom
  defp msg_type_atom(_), do: :MSG_TEXT

  defp clamp_limit(n) when is_integer(n) and n > 0, do: min(n, @max_limit)
  defp clamp_limit(_), do: @default_limit
end
