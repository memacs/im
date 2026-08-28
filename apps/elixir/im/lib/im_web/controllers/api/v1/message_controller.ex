defmodule IMWeb.Api.V1.MessageController do
  @moduledoc "消息 REST：发送 / 拉取 / ACK / 已读 / 撤回 / 编辑。"

  use IMWeb, :controller

  action_fallback(IMWeb.FallbackController)

  alias IM.Application.Dispatch
  alias IM.Domain.Error
  alias IMWeb.Api.V1.Json
  alias IM.WebSocket.Commands.MsgSend

  alias Pb.Im.Protocol.{
    ChatMessage,
    CmdType,
    MsgAck,
    MsgAckBatchUp,
    MsgEdit,
    MsgRead,
    MsgRecall,
    MsgSendReq,
    OfflinePullReq
  }

  @doc "`POST /api/v1/messages`"
  def create(conn, params) do
    ctx = conn.assigns.message_context
    msg = build_chat_message(params, ctx.user_id)
    cmd = CmdType.value(:CMD_MSG_SEND)

    case Dispatch.execute(cmd, %MsgSendReq{message: msg}, ctx) do
      {:ok, result = %{message: message, ack: ack, duplicate?: dup?}} ->
        unless dup? do
          _ = MsgSend.push_to_recipients(result, ctx.app_key, ctx.trace_id)
        end

        json(conn, %{
          msg_id: message.msg_id,
          client_msg_id: message.client_msg_id,
          conv_id: message.conv_id,
          conv_seq: message.conv_seq,
          server_time: message.server_time,
          status: ack_status(ack.status),
          duplicate: dup?
        })

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  @doc "`GET /api/v1/messages/inbox`"
  def inbox(conn, params) do
    pull(conn, %OfflinePullReq{
      conv_id: "",
      cursor: Json.int(params, "cursor", 0),
      limit: Json.int(params, "limit", 50)
    })
  end

  @doc "`GET /api/v1/conversations/:conv_id/messages`"
  def conversation_messages(conn, %{"conv_id" => conv_id} = params) do
    pull(conn, %OfflinePullReq{
      conv_id: conv_id,
      cursor: Json.int(params, "cursor", 0),
      limit: Json.int(params, "limit", 50)
    })
  end

  @doc "`POST /api/v1/messages/ack`"
  def ack(conn, params) do
    ctx = conn.assigns.message_context
    cmd = CmdType.value(:CMD_MSG_ACK_UP)

    ack = %MsgAck{
      msg_id: Json.str(params, "msg_id"),
      client_msg_id: Json.str(params, "client_msg_id"),
      status: :ACK_CLIENT_RECEIVED,
      conv_seq: Json.int(params, "conv_seq", 0)
    }

    case Dispatch.execute(cmd, ack, ctx) do
      {:ok, %{ack_down: down}} ->
        json(conn, Json.encode(down))

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  @doc "`POST /api/v1/messages/ack-batch`"
  def ack_batch(conn, params) do
    ctx = conn.assigns.message_context
    cmd = CmdType.value(:CMD_MSG_ACK_BATCH_UP)

    acks =
      (Map.get(params, "acks") || [])
      |> List.wrap()
      |> Enum.map(fn a ->
        %MsgAck{
          msg_id: Json.str(a, "msg_id"),
          client_msg_id: Json.str(a, "client_msg_id"),
          status: :ACK_CLIENT_RECEIVED,
          conv_seq: Json.int(a, "conv_seq", 0)
        }
      end)

    case Dispatch.execute(cmd, %MsgAckBatchUp{acks: acks}, ctx) do
      {:ok, %{batches: batches}} ->
        json(conn, %{
          batches:
            Enum.map(batches, fn {sender, batch} ->
              %{sender_user_id: sender, acks: Json.encode(batch.acks)}
            end)
        })

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  @doc "`POST /api/v1/messages/read`"
  def read(conn, params) do
    ctx = conn.assigns.message_context
    cmd = CmdType.value(:CMD_MSG_READ)

    read = %MsgRead{
      chat_type: chat_type_enum(params),
      from: ctx.user_id,
      to: Json.str(params, "to"),
      msg_id: Json.str(params, "msg_id"),
      conv_seq: Json.int(params, "conv_seq", 0),
      conv_id: Json.str(params, "conv_id")
    }

    case Dispatch.execute(cmd, read, ctx) do
      {:ok, result} ->
        payload = Map.get(result, :read) || Map.get(result, :msg_read) || result
        json(conn, Json.encode(payload))

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  @doc "`POST /api/v1/messages/:msg_id/recall`"
  def recall(conn, %{"msg_id" => msg_id} = params) do
    ctx = conn.assigns.message_context
    cmd = CmdType.value(:CMD_MSG_RECALL_REQ)

    req = %MsgRecall{
      msg_id: msg_id,
      reason: Json.str(params, "reason"),
      conv_id: Json.str(params, "conv_id")
    }

    case Dispatch.execute(cmd, req, ctx) do
      {:ok, %{recall: recall}} ->
        json(conn, Json.encode(recall))

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  @doc "`POST /api/v1/messages/:msg_id/edit`"
  def edit(conn, %{"msg_id" => msg_id} = params) do
    ctx = conn.assigns.message_context
    cmd = CmdType.value(:CMD_MSG_EDIT_REQ)

    content =
      case Map.get(params, "content") || Map.get(params, :content) || "" do
        bin when is_binary(bin) -> bin
        other -> to_string(other)
      end

    req = %MsgEdit{
      msg_id: msg_id,
      content: content,
      conv_id: Json.str(params, "conv_id")
    }

    case Dispatch.execute(cmd, req, ctx) do
      {:ok, %{edit: edit}} ->
        json(conn, Json.encode(edit))

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  defp pull(conn, %OfflinePullReq{} = req) do
    ctx = conn.assigns.message_context
    cmd = CmdType.value(:CMD_OFFLINE_PULL_REQ)

    case Dispatch.execute(cmd, req, ctx) do
      {:ok, resp} ->
        json(conn, %{
          messages: Enum.map(resp.messages, &encode_msg/1),
          next_cursor: resp.next_cursor,
          has_more: resp.has_more
        })

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  defp encode_msg(%ChatMessage{} = m) do
    %{
      msg_id: m.msg_id,
      client_msg_id: m.client_msg_id,
      chat_type: to_string(m.chat_type),
      from: m.from,
      to: m.to,
      conv_id: m.conv_id,
      content: if(is_binary(m.content) and String.valid?(m.content), do: m.content, else: ""),
      server_time: m.server_time,
      conv_seq: m.conv_seq,
      inbox_seq: m.inbox_seq
    }
  end

  defp build_chat_message(params, default_from) do
    content = Map.get(params, "content") || Map.get(params, :content) || ""

    content_bin =
      cond do
        is_binary(content) -> content
        true -> to_string(content)
      end

    %ChatMessage{
      client_msg_id: Json.str(params, "client_msg_id"),
      chat_type: chat_type_enum(params),
      from: Json.str(params, "from", default_from),
      to: Json.str(params, "to"),
      conv_id: Json.str(params, "conv_id"),
      msg_type: :MSG_TEXT,
      content: content_bin,
      target_users: target_users(params),
      burn_after_read: truthy?(params, "burn_after_read")
    }
  end

  defp target_users(params) do
    raw = Map.get(params, "target_users") || Map.get(params, :target_users) || []
    raw |> List.wrap() |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == ""))
  end

  defp chat_type_enum(params) do
    case Map.get(params, "chat_type") || Map.get(params, :chat_type) do
      "CHAT_GROUP" -> :CHAT_GROUP
      "group" -> :CHAT_GROUP
      2 -> :CHAT_GROUP
      "2" -> :CHAT_GROUP
      "CHAT_ROOM" -> :CHAT_ROOM
      "room" -> :CHAT_ROOM
      3 -> :CHAT_ROOM
      "3" -> :CHAT_ROOM
      _ -> :CHAT_PRIVATE
    end
  end

  defp truthy?(params, key) do
    case Map.get(params, key) || Map.get(params, String.to_atom(key)) do
      true -> true
      "true" -> true
      1 -> true
      _ -> false
    end
  end

  defp ack_status(:ACK_SERVER_RECEIVED), do: "SERVER_RECEIVED"
  defp ack_status(1), do: "SERVER_RECEIVED"
  defp ack_status(other), do: to_string(other)
end
