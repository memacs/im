defmodule IM.Services.MessageRead do
  @moduledoc "已读回执（P7-02）与阅后即焚触发。"

  alias IM.Domain.{Error, MessageContext}
  alias IM.Jobs.MessageBurn
  alias IM.Stores.{ConversationStore, MessageStore}
  alias Pb.Im.Protocol.MsgRead

  @doc """
  处理已读：更新位点、返回需推送的 MsgRead、调度 burn。

  ## 示例

      IM.Services.MessageRead.mark(read, ctx)
  """
  @spec mark(MsgRead.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def mark(%MsgRead{} = read, %MessageContext{} = ctx) do
    conv_id = read.conv_id
    conv_seq = read.conv_seq || 0

    if conv_id in [nil, ""] or conv_seq <= 0 do
      {:error, Error.new(:msg_invalid, "conv_id and conv_seq required")}
    else
      chat_type = chat_type_int(read.chat_type)
      peer = if read.to != "", do: read.to, else: nil

      {:ok, _} =
        ConversationStore.upsert_read(ctx.app_key, ctx.user_id, conv_id, conv_seq,
          chat_type: chat_type,
          peer_id: peer
        )

      unread = ConversationStore.get_unread(ctx.app_key, ctx.user_id, conv_id)

      down = %MsgRead{
        chat_type: read.chat_type,
        from: ctx.user_id,
        to: read.to,
        msg_id: read.msg_id,
        conv_seq: conv_seq,
        timestamp: System.system_time(:millisecond),
        conv_id: conv_id,
        unread_count: unread
      }

      # 阅后即焚：接收方已读覆盖
      burnables =
        MessageStore.list_burnable(ctx.app_key, conv_id, conv_seq)
        |> Enum.filter(fn b ->
          b.chat_type == 1 and b.from_uid != ctx.user_id and b.to_id == ctx.user_id
        end)

      Enum.each(burnables, fn b ->
        MessageBurn.schedule(ctx.app_key, b.msg_id, b.burn_ttl_sec || 0,
          from: b.from_uid,
          to: b.to_id,
          conv_id: b.conv_id
        )
      end)

      notify_user =
        case chat_type do
          1 -> other_private(ctx.user_id, read.from, read.to, conv_id)
          _ -> read.to
        end

      {:ok, %{read: down, notify_user_id: notify_user, exclude_device_id: ctx.device_id}}
    end
  end

  defp other_private(self, from, to, conv_id) do
    cond do
      to != "" and to != self ->
        to

      from != "" and from != self ->
        from

      true ->
        case String.split(conv_id, ":") do
          ["p", a, b] -> if a == self, do: b, else: a
          _ -> to
        end
    end
  end

  defp chat_type_int(:CHAT_PRIVATE), do: 1
  defp chat_type_int(:CHAT_GROUP), do: 2
  defp chat_type_int(1), do: 1
  defp chat_type_int(2), do: 2
  defp chat_type_int(_), do: 1
end
