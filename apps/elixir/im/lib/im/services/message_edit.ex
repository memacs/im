defmodule IM.Services.MessageEdit do
  @moduledoc "消息编辑（P7-04）。"

  alias IM.Domain.{Error, MessageContext}
  alias IM.Stores.MessageStore
  alias Pb.Im.Protocol.MsgEdit

  @doc """
  编辑消息。
  """
  @spec edit(MsgEdit.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def edit(%MsgEdit{} = req, %MessageContext{} = ctx) do
    window = Application.get_env(:im, :edit_window_sec, 120)

    with {:ok, body} <- MessageStore.get_by_msg_id(ctx.app_key, req.msg_id),
         :ok <- authorize(body, ctx.user_id),
         :ok <- check_window(body, window),
         {:ok, updated} <- MessageStore.mark_edited(ctx.app_key, req.msg_id, req.content || <<>>) do
      push = %MsgEdit{
        msg_id: updated.msg_id,
        chat_type: chat_type(updated.chat_type),
        from: updated.from_uid,
        to: updated.to_id,
        msg_type: :MSG_TEXT,
        content: updated.content,
        timestamp: System.system_time(:millisecond),
        edit_version: updated.edit_version,
        conv_id: updated.conv_id
      }

      recipients =
        case updated.chat_type do
          1 -> Enum.uniq([updated.from_uid, updated.to_id])
          2 -> IM.Group.MemberCache.list_member_ids(updated.app_key, updated.to_id)
          _ -> [updated.from_uid, updated.to_id]
        end

      {:ok, %{edit: push, recipient_user_ids: recipients, exclude_device_id: ctx.device_id}}
    else
      {:error, :not_found} -> {:error, Error.new(:msg_invalid, "msg not found")}
      {:error, :burned} -> {:error, Error.new(:msg_edit_denied, "burn message not editable")}
      {:error, %Error{}} = err -> err
    end
  end

  defp authorize(body, user_id) do
    if body.from_uid == user_id,
      do: :ok,
      else: {:error, Error.new(:msg_edit_denied, "not sender")}
  end

  defp check_window(body, window) do
    age_ms = System.system_time(:millisecond) - (body.server_time || 0)

    if age_ms <= window * 1000 do
      :ok
    else
      {:error, Error.new(:msg_edit_denied, "edit window exceeded")}
    end
  end

  defp chat_type(1), do: :CHAT_PRIVATE
  defp chat_type(2), do: :CHAT_GROUP
  defp chat_type(3), do: :CHAT_ROOM
  defp chat_type(_), do: :CHAT_PRIVATE
end
