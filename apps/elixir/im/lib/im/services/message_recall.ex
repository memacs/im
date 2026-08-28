defmodule IM.Services.MessageRecall do
  @moduledoc "消息撤回（P7-03）；群/室管理员可撤回他人消息（recall.md §2）。"

  alias IM.Domain.{Error, MessageContext}
  alias IM.Stores.{GroupStore, MessageStore, RoomStore}
  alias Pb.Im.Protocol.MsgRecall

  @doc """
  撤回消息。
  """
  @spec recall(MsgRecall.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def recall(%MsgRecall{} = req, %MessageContext{} = ctx) do
    window = Application.get_env(:im, :recall_window_sec, 120)

    with {:ok, body} <- MessageStore.get_by_msg_id(ctx.app_key, req.msg_id),
         :ok <- authorize_recall(body, ctx),
         :ok <- check_window(body, window),
         :ok <- reject_if_burned(body),
         {:ok, updated} <- MessageStore.mark_recalled(ctx.app_key, req.msg_id) do
      push = %MsgRecall{
        msg_id: updated.msg_id,
        chat_type: chat_type(updated.chat_type),
        from: updated.from_uid,
        to: updated.to_id,
        timestamp: System.system_time(:millisecond),
        reason: req.reason || "",
        conv_id: updated.conv_id
      }

      recipients = recipients_for(updated)
      {:ok, %{recall: push, recipient_user_ids: recipients, exclude_device_id: ctx.device_id}}
    else
      {:error, :not_found} -> {:error, Error.new(:msg_invalid, "msg not found")}
      {:error, %Error{}} = err -> err
    end
  end

  defp authorize_recall(body, ctx) do
    if body.from_uid == ctx.user_id do
      :ok
    else
      authorize_admin_recall(body, ctx)
    end
  end

  defp authorize_admin_recall(%{chat_type: 2, to_id: group_id} = _body, ctx) do
    admin_role = GroupStore.role_admin()

    case GroupStore.get_member(ctx.app_key, group_id, ctx.user_id) do
      {:ok, %{role: role}} when role >= admin_role ->
        :ok

      _ ->
        {:error, Error.new(:msg_recall_denied, "not sender or group admin")}
    end
  end

  defp authorize_admin_recall(%{chat_type: 3, to_id: room_id} = _body, ctx) do
    case RoomStore.get(ctx.app_key, room_id) do
      {:ok, %{owner_uid: owner}} when owner == ctx.user_id ->
        :ok

      _ ->
        {:error, Error.new(:msg_recall_denied, "not sender or room owner")}
    end
  end

  defp authorize_admin_recall(_body, _ctx) do
    {:error, Error.new(:msg_recall_denied, "not sender")}
  end

  defp check_window(body, window) do
    age_ms = System.system_time(:millisecond) - (body.server_time || 0)

    if age_ms <= window * 1000 do
      :ok
    else
      {:error, Error.new(:msg_recall_denied, "recall window exceeded")}
    end
  end

  defp reject_if_burned(%{burned: true}), do: {:error, Error.new(:msg_recall_denied, "already burned")}
  defp reject_if_burned(_), do: :ok

  defp recipients_for(%{chat_type: 1, from_uid: from, to_id: to}), do: Enum.uniq([from, to])
  defp recipients_for(%{chat_type: 2} = b), do: IM.Group.MemberCache.list_member_ids(b.app_key, b.to_id)
  defp recipients_for(%{from_uid: from, to_id: to}), do: Enum.uniq([from, to])

  defp chat_type(1), do: :CHAT_PRIVATE
  defp chat_type(2), do: :CHAT_GROUP
  defp chat_type(3), do: :CHAT_ROOM
  defp chat_type(_), do: :CHAT_PRIVATE
end
