defmodule IM.Stores.MessageStore do
  @moduledoc "message_bodies + user_inbox 持久化。"

  import Ecto.Query

  alias IM.Domain.Error
  alias IM.Group.FanoutConfig
  alias IM.Repo
  alias IM.Schemas.{MessageBody, UserInbox}
  alias IM.Services.Sequence
  alias IM.Telemetry.Storage

  @doc """
  按 msg_id 查找正文。

  ## 示例

      IM.Stores.MessageStore.get_by_msg_id("a", "m1")
  """
  @spec get_by_msg_id(String.t(), String.t()) :: {:ok, MessageBody.t()} | {:error, :not_found}
  def get_by_msg_id(app_key, msg_id) do
    Storage.span(:query, "message_store", fn ->
      case Repo.get_by(MessageBody, app_key: app_key, msg_id: msg_id) do
        nil -> {:error, :not_found}
        body -> {:ok, body}
      end
    end)
  end

  @doc """
  批量读取消息预览（会话列表回填）。

  返回 `%{msg_id => preview}`。
  """
  @spec previews_by_msg_ids(String.t(), [String.t()]) :: %{String.t() => String.t()}
  def previews_by_msg_ids(_app_key, []), do: %{}

  def previews_by_msg_ids(app_key, msg_ids) when is_binary(app_key) and is_list(msg_ids) do
    ids = msg_ids |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()

    if ids == [] do
      %{}
    else
      alias IM.Conversation.Preview

      from(b in MessageBody,
        where: b.app_key == ^app_key and b.msg_id in ^ids,
        select: {b.msg_id, b.msg_type, b.content, b.recalled}
      )
      |> Repo.all()
      |> Map.new(fn {id, type, content, recalled} ->
        {id, Preview.from_body(type, content, recalled == true)}
      end)
    end
  end

  @doc """
  按业务幂等键查找正文。

  ## 示例

      IM.Stores.MessageStore.get_by_client_msg_id("a", "u", "c1")
  """
  @spec get_by_client_msg_id(String.t(), String.t(), String.t()) ::
          {:ok, MessageBody.t()} | {:error, :not_found}
  def get_by_client_msg_id(app_key, from_uid, client_msg_id) do
    Storage.span(:query, "message_store", fn ->
      case Repo.get_by(MessageBody,
             app_key: app_key,
             from_uid: from_uid,
             client_msg_id: client_msg_id
           ) do
        nil -> {:error, :not_found}
        body -> {:ok, body}
      end
    end)
  end

  @doc """
  标记撤回。
  """
  @spec mark_recalled(String.t(), String.t()) :: {:ok, MessageBody.t()} | {:error, :not_found}
  def mark_recalled(app_key, msg_id) do
    with {:ok, body} <- get_by_msg_id(app_key, msg_id) do
      body
      |> MessageBody.changeset(%{recalled: true})
      |> Repo.update()
      |> case do
        {:ok, b} -> {:ok, b}
        _ -> {:error, :not_found}
      end
    end
  end

  @doc """
  编辑正文并递增 edit_version。
  """
  @spec mark_edited(String.t(), String.t(), binary()) ::
          {:ok, MessageBody.t()} | {:error, :not_found | :burned}
  def mark_edited(app_key, msg_id, content) when is_binary(content) do
    with {:ok, body} <- get_by_msg_id(app_key, msg_id) do
      if body.burned or body.burn_after_read do
        {:error, :burned}
      else
        body
        |> MessageBody.changeset(%{
          content: content,
          edit_version: (body.edit_version || 0) + 1
        })
        |> Repo.update()
        |> case do
          {:ok, b} -> {:ok, b}
          _ -> {:error, :not_found}
        end
      end
    end
  end

  @doc """
  阅后即焚销毁（墓碑）。
  """
  @spec mark_burned(String.t(), String.t()) :: {:ok, MessageBody.t()} | {:error, :not_found}
  def mark_burned(app_key, msg_id) do
    with {:ok, body} <- get_by_msg_id(app_key, msg_id) do
      if body.burned do
        {:ok, body}
      else
        # cast(<<>>) 会被当成 blank→nil；force_change 保留空正文墓碑
        body
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.force_change(:burned, true)
        |> Ecto.Changeset.force_change(:content, <<>>)
        |> Ecto.Changeset.force_change(
          :burn_at,
          DateTime.utc_now() |> DateTime.truncate(:microsecond)
        )
        |> Repo.update()
        |> case do
          {:ok, b} -> {:ok, b}
          _ -> {:error, :not_found}
        end
      end
    end
  end

  @doc """
  会话内待焚毁且已被已读位点覆盖的消息。
  """
  @spec list_burnable(String.t(), String.t(), non_neg_integer()) :: [MessageBody.t()]
  def list_burnable(app_key, conv_id, read_conv_seq) do
    from(b in MessageBody,
      where:
        b.app_key == ^app_key and b.conv_id == ^conv_id and b.burn_after_read == true and
          b.burned == false and b.recalled == false and b.conv_seq <= ^read_conv_seq
    )
    |> Repo.all()
  end

  @doc """
  TTL：选出过期 msg_id（单聊/群聊）。
  """
  @spec list_expired_msg_ids(String.t(), DateTime.t(), pos_integer()) :: [String.t()]
  def list_expired_msg_ids(app_key, cutoff, limit) do
    from(b in MessageBody,
      where: b.app_key == ^app_key and b.inserted_at < ^cutoff and b.chat_type in [1, 2],
      select: b.msg_id,
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  删除给定 msg_id 的 inbox 与 bodies。
  """
  @spec delete_messages(String.t(), [String.t()]) :: %{
          inbox: non_neg_integer(),
          bodies: non_neg_integer()
        }
  def delete_messages(app_key, msg_ids) when is_list(msg_ids) do
    {inbox, _} =
      from(i in UserInbox, where: i.app_key == ^app_key and i.msg_id in ^msg_ids)
      |> Repo.delete_all()

    {bodies, _} =
      from(b in MessageBody, where: b.app_key == ^app_key and b.msg_id in ^msg_ids)
      |> Repo.delete_all()

    %{inbox: inbox, bodies: bodies}
  end

  @doc """
  删除过期聊天室短缓存正文。
  """
  @spec delete_expired_room_bodies(DateTime.t(), pos_integer()) :: non_neg_integer()
  def delete_expired_room_bodies(cutoff, limit) do
    ids =
      from(b in MessageBody,
        where: b.chat_type == 3 and b.inserted_at < ^cutoff,
        select: %{app_key: b.app_key, msg_id: b.msg_id},
        limit: ^limit
      )
      |> Repo.all()

    Enum.reduce(ids, 0, fn %{app_key: a, msg_id: m}, acc ->
      {n, _} =
        from(b in MessageBody, where: b.app_key == ^a and b.msg_id == ^m)
        |> Repo.delete_all()

      acc + n
    end)
  end

  @doc """
  插入单聊：1 body + 双方 inbox。

  ## 示例

      IM.Stores.MessageStore.insert_private(attrs, ["u1", "u2"])
  """
  @spec insert_private(map(), [String.t()]) ::
          {:ok, %{body: MessageBody.t(), inbox: [UserInbox.t()], duplicate?: boolean()}}
          | {:error, Error.t()}
  def insert_private(body_attrs, recipient_user_ids)
      when is_map(body_attrs) and is_list(recipient_user_ids) do
    insert_with_inbox(body_attrs, recipient_user_ids)
  end

  @doc """
  插入群聊写扩散：1 body + N inbox。

  ## 示例

      IM.Stores.MessageStore.insert_group(attrs, ["u1", "u2", "u3"])
  """
  @spec insert_group(map(), [String.t()]) ::
          {:ok, %{body: MessageBody.t(), inbox: [UserInbox.t()], duplicate?: boolean()}}
          | {:error, Error.t()}
  def insert_group(body_attrs, recipient_user_ids)
      when is_map(body_attrs) and is_list(recipient_user_ids) do
    insert_with_inbox(body_attrs, recipient_user_ids)
  end

  @doc """
  通用：1 body + 指定用户 inbox 写扩散。
  """
  @spec insert_with_inbox(map(), [String.t()]) ::
          {:ok, %{body: MessageBody.t(), inbox: [UserInbox.t()], duplicate?: boolean()}}
          | {:error, Error.t()}
  def insert_with_inbox(body_attrs, recipient_user_ids)
      when is_map(body_attrs) and is_list(recipient_user_ids) do
    do_insert(body_attrs, recipient_user_ids)
  end

  @doc """
  仅写正文（读扩散大群）。

  ## 示例

      IM.Stores.MessageStore.insert_body_only(attrs)
  """
  @spec insert_body_only(map()) ::
          {:ok, %{body: MessageBody.t(), inbox: [], duplicate?: boolean()}} | {:error, Error.t()}
  def insert_body_only(body_attrs) when is_map(body_attrs) do
    Storage.span(:insert, "message_store", fn ->
      changeset =
        %MessageBody{}
        |> MessageBody.changeset(Map.new(body_attrs))
        |> Ecto.Changeset.unique_constraint([:app_key, :from_uid, :client_msg_id],
          name: :idx_message_bodies_client_msg
        )

      case Repo.insert(changeset) do
        {:ok, body} ->
          {:ok, %{body: body, inbox: [], duplicate?: false}}

        {:error, %Ecto.Changeset{errors: errors}} ->
          if Keyword.has_key?(errors, :client_msg_id) or Keyword.has_key?(errors, :app_key) do
            {:error, Error.new(:msg_invalid, "duplicate client_msg_id")}
          else
            {:error, Error.new(:internal_error, inspect(errors))}
          end
      end
    end)
  end

  @doc """
  读扩散：按 conv_seq 直查 bodies（含定向可见性过滤）。
  """
  @spec list_bodies_by_conv_seq(
          String.t(),
          String.t(),
          non_neg_integer(),
          pos_integer(),
          String.t()
        ) :: [map()]
  def list_bodies_by_conv_seq(app_key, conv_id, after_seq, limit, viewer_uid) do
    from(b in MessageBody,
      where: b.app_key == ^app_key and b.conv_id == ^conv_id and b.conv_seq > ^after_seq,
      where:
        is_nil(b.target_users) or b.from_uid == ^viewer_uid or
          fragment("? = ANY(?)", ^viewer_uid, b.target_users),
      order_by: [asc: b.conv_seq],
      limit: ^limit,
      select: %{body: b, inbox_seq: 0}
    )
    |> Repo.all()
  end

  @doc """
  按 inbox_seq 拉取。

  ## 示例

      IM.Stores.MessageStore.list_by_inbox_seq("a", "u", 0, 50)
  """
  @spec list_by_inbox_seq(String.t(), String.t(), non_neg_integer(), pos_integer()) ::
          [map()]
  def list_by_inbox_seq(app_key, user_id, after_seq, limit) do
    Storage.span(:query, "message_store", fn ->
      from(i in UserInbox,
        join: b in MessageBody,
        on: b.app_key == i.app_key and b.msg_id == i.msg_id,
        where: i.app_key == ^app_key and i.user_id == ^user_id and i.inbox_seq > ^after_seq,
        order_by: [asc: i.inbox_seq],
        limit: ^limit,
        select: %{body: b, inbox_seq: i.inbox_seq}
      )
      |> Repo.all()
    end)
  end

  @doc """
  按会话 conv_seq 拉取。

  ## 示例

      IM.Stores.MessageStore.list_by_conv_seq("a", "u", "p:a:b", 0, 50)
  """
  @spec list_by_conv_seq(String.t(), String.t(), String.t(), non_neg_integer(), pos_integer()) ::
          [map()]
  def list_by_conv_seq(app_key, user_id, conv_id, after_seq, limit) do
    from(i in UserInbox,
      join: b in MessageBody,
      on: b.app_key == i.app_key and b.msg_id == i.msg_id,
      where:
        i.app_key == ^app_key and i.user_id == ^user_id and i.conv_id == ^conv_id and
          i.conv_seq > ^after_seq,
      order_by: [asc: i.conv_seq],
      limit: ^limit,
      select: %{body: b, inbox_seq: i.inbox_seq}
    )
    |> Repo.all()
  end

  @doc """
  仅为已有正文补写 inbox 行（异步扇出用）。
  """
  @spec insert_inbox_rows(map(), [String.t()]) :: :ok | {:error, term()}
  def insert_inbox_rows(body_attrs, recipient_user_ids)
      when is_map(body_attrs) and is_list(recipient_user_ids) do
    app_key = body_attrs[:app_key] || body_attrs["app_key"]
    conv_id = body_attrs[:conv_id] || body_attrs["conv_id"]
    msg_id = body_attrs[:msg_id] || body_attrs["msg_id"]
    conv_seq = body_attrs[:conv_seq] || body_attrs["conv_seq"]
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    rows =
      Enum.map(recipient_user_ids, fn uid ->
        %{
          app_key: app_key,
          user_id: uid,
          msg_id: msg_id,
          conv_id: conv_id,
          inbox_seq: Sequence.next(app_key, "inbox_seq", uid),
          conv_seq: conv_seq,
          created_at: now
        }
      end)

    chunk = FanoutConfig.get(:inbox_insert_chunk)

    Enum.each(Enum.chunk_every(rows, chunk), fn part ->
      Repo.insert_all(UserInbox, part, on_conflict: :nothing)
    end)

    :ok
  rescue
    e -> {:error, e}
  end

  defp do_insert(body_attrs, recipient_user_ids) do
    Storage.span(:insert, "message_store", fn ->
      do_insert_unmeasured(body_attrs, recipient_user_ids)
    end)
  end

  defp do_insert_unmeasured(body_attrs, recipient_user_ids) do
    app_key = body_attrs[:app_key] || body_attrs["app_key"]
    conv_id = body_attrs[:conv_id] || body_attrs["conv_id"]
    msg_id = body_attrs[:msg_id] || body_attrs["msg_id"]
    conv_seq = body_attrs[:conv_seq] || body_attrs["conv_seq"]
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.transaction(fn ->
      changeset =
        %MessageBody{}
        |> MessageBody.changeset(Map.new(body_attrs))
        |> Ecto.Changeset.unique_constraint([:app_key, :from_uid, :client_msg_id],
          name: :idx_message_bodies_client_msg
        )

      case Repo.insert(changeset) do
        {:ok, body} ->
          rows =
            Enum.map(recipient_user_ids, fn uid ->
              %{
                app_key: app_key,
                user_id: uid,
                msg_id: msg_id,
                conv_id: conv_id,
                inbox_seq: Sequence.next(app_key, "inbox_seq", uid),
                conv_seq: conv_seq,
                created_at: now
              }
            end)

          chunk = FanoutConfig.get(:inbox_insert_chunk)

          inbox =
            rows
            |> Enum.chunk_every(chunk)
            |> Enum.flat_map(fn part ->
              {_count, inserted} = Repo.insert_all(UserInbox, part, returning: true)
              inserted
            end)

          %{body: body, inbox: inbox, duplicate?: false}

        {:error, %Ecto.Changeset{errors: errors}} ->
          if Keyword.has_key?(errors, :client_msg_id) or
               Keyword.has_key?(errors, :app_key) do
            Repo.rollback(:duplicate_client_msg_id)
          else
            Repo.rollback({:changeset, errors})
          end
      end
    end)
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:error, :duplicate_client_msg_id} ->
        {:error, Error.new(:msg_invalid, "duplicate client_msg_id")}

      {:error, reason} ->
        {:error, Error.new(:internal_error, inspect(reason))}
    end
  end
end
