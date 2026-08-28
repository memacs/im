defmodule IMWeb.Api.V1.ConversationController do
  @moduledoc "`GET /api/v1/conversations` 会话列表。"

  use IMWeb, :controller

  action_fallback(IMWeb.FallbackController)

  alias IM.Services.Conversation
  alias IMWeb.Api.V1.Json

  @doc "`GET /api/v1/conversations`"
  def index(conn, params) do
    ctx = conn.assigns.message_context
    limit = Json.int(params, "limit", 100)

    {:ok, %{conversations: rows, total_unread: total}} =
      Conversation.list(ctx, limit: limit)

    json(conn, %{
      conversations: Enum.map(rows, &render_conv/1),
      total_unread: total
    })
  end

  defp render_conv({row, unread, preview}) do
    %{
      conv_id: row.conv_id,
      chat_type: row.chat_type,
      peer_id: row.peer_id,
      last_msg_id: row.last_msg_id,
      last_msg_type: row.last_msg_type,
      last_msg_preview: preview,
      last_msg_time: row.last_msg_time,
      last_msg_seq: row.last_msg_seq,
      last_read_conv_seq: row.last_read_conv_seq || 0,
      unread_count: unread
    }
  end
end
