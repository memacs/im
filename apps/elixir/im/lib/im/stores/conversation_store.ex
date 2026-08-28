defmodule IM.Stores.ConversationStore do
  @moduledoc "会话已读位点与未读计数。"

  import Ecto.Query

  alias IM.Conversation.{Preview, UnreadCache}
  alias IM.Repo
  alias IM.Schemas.Conversation

  @doc """
  更新已读位点（只增不减），并将 unread_count 置 0。
  """
  @spec upsert_read(String.t(), String.t(), String.t(), non_neg_integer(), keyword()) ::
          {:ok, Conversation.t()} | {:error, term()}
  def upsert_read(app_key, user_id, conv_id, conv_seq, opts \\ []) do
    chat_type = Keyword.get(opts, :chat_type, 1)
    peer_id = Keyword.get(opts, :peer_id)

    result =
      case Repo.get_by(Conversation, app_key: app_key, user_id: user_id, conv_id: conv_id) do
        nil ->
          %Conversation{}
          |> Conversation.changeset(%{
            app_key: app_key,
            user_id: user_id,
            chat_type: chat_type,
            conv_id: conv_id,
            peer_id: peer_id,
            last_read_conv_seq: conv_seq,
            unread_count: 0
          })
          |> Repo.insert()

        %Conversation{last_read_conv_seq: old} = conv ->
          new_seq = max(old || 0, conv_seq)

          conv
          |> Conversation.changeset(%{last_read_conv_seq: new_seq, unread_count: 0})
          |> Repo.update()
      end

    :ok = UnreadCache.reset(app_key, user_id, conv_id)
    result
  end

  @doc """
  收件人未读 +1。热路径 Redis INCR；确保 PG 有会话行供列表查询。
  """
  @spec bump_unread(String.t(), String.t(), String.t(), keyword()) :: :ok
  def bump_unread(app_key, user_id, conv_id, opts \\ [])
      when is_binary(app_key) and is_binary(user_id) and is_binary(conv_id) do
    :ok = UnreadCache.incr(app_key, user_id, conv_id)
    :ok = ensure_conv_row(app_key, user_id, conv_id, opts)
    :ok = touch_last_msg(app_key, user_id, conv_id, opts)
    :ok
  end

  @doc "批量收件人未读 +1（群扇出等，合并 touch last_msg）。"
  @spec bump_unread_many(String.t(), [String.t()], String.t(), keyword()) :: :ok
  def bump_unread_many(app_key, user_ids, conv_id, opts \\ [])
      when is_binary(app_key) and is_binary(conv_id) and is_list(user_ids) do
    user_ids =
      user_ids
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    Enum.each(user_ids, fn uid ->
      :ok = UnreadCache.incr(app_key, uid, conv_id)
    end)

    :ok = ensure_conv_rows(app_key, user_ids, conv_id, opts)
    :ok = touch_last_msg_many(app_key, user_ids, conv_id, opts)
    :ok
  end

  @doc "发送方更新 last_msg 元数据（不增未读）。"
  @spec touch_sender_conv(String.t(), String.t(), String.t(), keyword()) :: :ok
  def touch_sender_conv(app_key, user_id, conv_id, opts \\ [])
      when is_binary(app_key) and is_binary(user_id) and is_binary(conv_id) do
    :ok = ensure_conv_row(app_key, user_id, conv_id, opts)
    :ok = touch_last_msg(app_key, user_id, conv_id, opts)
    :ok
  end

  @doc "读取未读（PG 基线 + Redis pending）。"
  @spec get_unread(String.t(), String.t(), String.t()) :: non_neg_integer()
  def get_unread(app_key, user_id, conv_id) do
    pg_base =
      case Repo.get_by(Conversation, app_key: app_key, user_id: user_id, conv_id: conv_id) do
        %{unread_count: n} when is_integer(n) and n > 0 -> n
        _ -> 0
      end

    pg_base + UnreadCache.pending(app_key, user_id, conv_id)
  end

  @doc "用户会话列表（按 `updated_at` 降序）。"
  @spec list_for_user(String.t(), String.t(), keyword()) :: [Conversation.t()]
  def list_for_user(app_key, user_id, opts \\ [])
      when is_binary(app_key) and is_binary(user_id) do
    limit = Keyword.get(opts, :limit, 100)

    from(c in Conversation,
      where: c.app_key == ^app_key and c.user_id == ^user_id,
      order_by: [desc: c.updated_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  将 Redis pending 合并写入 PG（Oban 刷库）。

  返回 `%{flushed: n, skipped: m}`。
  """
  @spec flush_pending(String.t(), keyword()) :: %{
          flushed: non_neg_integer(),
          skipped: non_neg_integer()
        }
  def flush_pending(app_key, opts \\ []) when is_binary(app_key) do
    batch = Keyword.get(opts, :batch, 500)

    UnreadCache.list_dirty(app_key, batch)
    |> Enum.reduce(%{flushed: 0, skipped: 0}, fn {user_id, conv_id}, acc ->
      case flush_one(app_key, user_id, conv_id) do
        :flushed -> %{acc | flushed: acc.flushed + 1}
        :skipped -> %{acc | skipped: acc.skipped + 1}
      end
    end)
  end

  defp flush_one(app_key, user_id, conv_id) do
    pending = UnreadCache.pending(app_key, user_id, conv_id)

    if pending == 0 do
      :ok = UnreadCache.reset(app_key, user_id, conv_id)
      :skipped
    else
      total = get_unread(app_key, user_id, conv_id)

      case Repo.get_by(Conversation, app_key: app_key, user_id: user_id, conv_id: conv_id) do
        nil ->
          :skipped

        %Conversation{} = conv ->
          case conv |> Conversation.changeset(%{unread_count: total}) |> Repo.update() do
            {:ok, _} ->
              :ok = UnreadCache.reset(app_key, user_id, conv_id)
              :flushed

            {:error, _} ->
              :skipped
          end
      end
    end
  end

  defp ensure_conv_row(app_key, user_id, conv_id, opts) do
    chat_type = Keyword.get(opts, :chat_type, 1)
    peer_id = Keyword.get(opts, :peer_id)

    case Repo.get_by(Conversation, app_key: app_key, user_id: user_id, conv_id: conv_id) do
      %Conversation{} ->
        :ok

      nil ->
        insert_conv_row(app_key, user_id, conv_id, chat_type, peer_id)
    end
  end

  defp ensure_conv_rows(app_key, user_ids, conv_id, opts) do
    chat_type = Keyword.get(opts, :chat_type, 1)
    peer_id = Keyword.get(opts, :peer_id)

    existing =
      from(c in Conversation,
        where: c.app_key == ^app_key and c.conv_id == ^conv_id and c.user_id in ^user_ids,
        select: c.user_id
      )
      |> Repo.all()
      |> MapSet.new()

    missing = Enum.reject(user_ids, &MapSet.member?(existing, &1))

    if missing == [] do
      :ok
    else
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      rows =
        Enum.map(missing, fn uid ->
          %{
            app_key: app_key,
            user_id: uid,
            chat_type: chat_type,
            conv_id: conv_id,
            peer_id: peer_id,
            last_read_conv_seq: 0,
            unread_count: 0,
            inserted_at: now,
            updated_at: now
          }
        end)

      _ = Repo.insert_all(Conversation, rows, on_conflict: :nothing)
      :ok
    end
  end

  defp insert_conv_row(app_key, user_id, conv_id, chat_type, peer_id) do
    %Conversation{}
    |> Conversation.changeset(%{
      app_key: app_key,
      user_id: user_id,
      chat_type: chat_type,
      conv_id: conv_id,
      peer_id: peer_id,
      last_read_conv_seq: 0,
      unread_count: 0
    })
    |> Repo.insert()
    |> case do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp touch_last_msg(app_key, user_id, conv_id, opts) do
    touch_last_msg_many(app_key, [user_id], conv_id, opts)
  end

  defp touch_last_msg_many(_app_key, [], _conv_id, _opts), do: :ok

  defp touch_last_msg_many(app_key, user_ids, conv_id, opts) do
    msg_id = Keyword.get(opts, :msg_id)
    server_time = Keyword.get(opts, :server_time)
    conv_seq = Keyword.get(opts, :conv_seq)
    msg_type = Keyword.get(opts, :msg_type)
    preview = preview_from_opts(opts)

    if is_binary(msg_id) and msg_id != "" and is_integer(server_time) and is_integer(conv_seq) do
      {_, _} =
        from(c in Conversation,
          where:
            c.app_key == ^app_key and c.conv_id == ^conv_id and c.user_id in ^user_ids and
              (is_nil(c.last_msg_time) or c.last_msg_time < ^server_time)
        )
        |> Repo.update_all(
          set: [
            last_msg_id: msg_id,
            last_msg_type: msg_type,
            last_msg_preview: preview,
            last_msg_time: server_time,
            last_msg_seq: conv_seq,
            updated_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
          ]
        )

      :ok
    else
      :ok
    end
  end

  defp preview_from_opts(opts) do
    case Keyword.get(opts, :preview) do
      p when is_binary(p) -> p
      _ -> Preview.from_message(Keyword.get(opts, :msg_type), Keyword.get(opts, :content), false)
    end
  end
end
