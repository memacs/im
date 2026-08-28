defmodule IM.Services.Conversation do
  @moduledoc "会话列表查询（REST / 多端同步）。"

  alias IM.Domain.MessageContext
  alias IM.Stores.{ConversationStore, MessageStore}

  @doc """
  列出当前用户会话，未读数为 PG + Redis 合并值。

  ## 示例

      IM.Services.Conversation.list(ctx, limit: 50)
  """
  @spec list(MessageContext.t(), keyword()) :: {:ok, map()}
  def list(%MessageContext{} = ctx, opts \\ []) do
    rows = ConversationStore.list_for_user(ctx.app_key, ctx.user_id, opts)

    preview_fallback =
      rows
      |> Enum.filter(fn r ->
        r.last_msg_id not in [nil, ""] and r.last_msg_preview in [nil, ""]
      end)
      |> Enum.map(& &1.last_msg_id)
      |> then(&MessageStore.previews_by_msg_ids(ctx.app_key, &1))

    enriched =
      Enum.map(rows, fn row ->
        unread = ConversationStore.get_unread(ctx.app_key, ctx.user_id, row.conv_id)
        preview = row.last_msg_preview || Map.get(preview_fallback, row.last_msg_id)
        {row, unread, preview}
      end)

    total_unread = enriched |> Enum.map(fn {_, u, _} -> u end) |> Enum.sum()

    {:ok,
     %{
       conversations: enriched,
       total_unread: total_unread
     }}
  end
end
