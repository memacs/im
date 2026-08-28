defmodule IM.Services.Message do
  @moduledoc """
  单聊发消息与 ACK_UP 处理（Phase 3）。

  SEND 路径同步：校验 → cid/业务幂等 → 落库 → 返回 ACK 载荷；由 Command/REST 负责写出与 PUSH。
  """

  require IM.Log

  alias IM.Domain.{ConvId, Error, MessageContext}
  alias IM.EventBus
  alias IM.Gateway.CidDedup
  alias IM.Group.FanoutPolicy
  alias IM.Hooks.PreSend
  alias IM.Jobs.GroupInboxFanout
  alias IM.Services.{Friend, MsgId, Sequence, StreamManager}
  alias IM.Group.{MemberCache, MetaCache}
  alias IM.Room.MemberCache, as: RoomMemberCache
  alias IM.Room.MetaCache, as: RoomMetaCache
  alias IM.Message.ClientMsgIdCache
  alias IM.Stores.{ConversationStore, MessageStore}
  alias Pb.Im.Protocol.StreamContent
  alias IM.Telemetry.Message, as: MsgTelemetry
  alias Pb.Im.Protocol.{ChatMessage, ChatType, MsgAck, MsgType}

  @doc """
  发送单聊消息。成功返回 `%{message, ack, duplicate?, peer_user_id, ...}`。

  ## 示例

      IM.Services.Message.send(chat_message, ctx, cid: "c1")
  """
  @spec send(ChatMessage.t(), MessageContext.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def send(%ChatMessage{} = msg, %MessageContext{} = ctx, opts \\ []) do
    start = System.monotonic_time()
    cid = Keyword.get(opts, :cid, "")
    conn_id = ctx.session_id || ctx.device_id || "anon"

    with :ok <- CidDedup.check(conn_id, cid),
         {:ok, msg, recipients, storage_mode} <- validate_and_recipients(msg, ctx),
         {:ok, msg} <- PreSend.run(msg, ctx) do
      case persist_new(msg, ctx, recipients, storage_mode) do
        {:ok, persisted} ->
          ack = %MsgAck{
            msg_id: persisted.message.msg_id,
            client_msg_id: persisted.message.client_msg_id,
            status: :ACK_SERVER_RECEIVED,
            conv_seq: persisted.message.conv_seq
          }

          MsgTelemetry.send_to_server_ack(start, 1)

          peer_user_id =
            case msg.chat_type do
              :CHAT_PRIVATE -> msg.to
              _ -> nil
            end

          # 旁路：失败/禁用/write_kafka=false 均不阻塞 ACK
          _ =
            EventBus.publish(
              :upstream,
              %{
                msg_id: persisted.message.msg_id,
                conv_id: persisted.message.conv_id,
                chat_type: msg.chat_type,
                app_key: ctx.app_key,
                from: ctx.user_id,
                device_id: ctx.device_id,
                trace_id: ctx.trace_id,
                duplicate?: persisted.duplicate?
              },
              write_kafka: Map.get(ctx, :write_kafka, true) != false
            )

          {:ok,
           %{
             message: persisted.message,
             ack: ack,
             duplicate?: persisted.duplicate?,
             inbox_seqs: persisted.inbox_seqs,
             recipient_user_ids: recipients,
             peer_user_id: peer_user_id,
             sender_user_id: ctx.user_id,
             sender_device_id: ctx.device_id
           }}

        {:error, %Error{code: :internal_error} = err} ->
          IM.Log.error(:storage_failed,
            reason: err.msg || "persist_failed",
            app_key: ctx.app_key,
            user_id: ctx.user_id
          )

          {:error, err}

        {:error, %Error{}} = err ->
          err
      end
    else
      :duplicate ->
        {:error, Error.new(:msg_invalid, "duplicate packet cid")}

      {:error, %Error{}} = err ->
        err
    end
  end

  @doc """
  处理接收方 ACK_UP → 构造发给发送方的 CLIENT_RECEIVED ACK。

  ## 示例

      IM.Services.Message.ack_up(ack, ctx)
  """
  @spec ack_up(MsgAck.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def ack_up(%MsgAck{} = ack, %MessageContext{} = ctx) do
    start = System.monotonic_time()

    unless client_received?(ack.status) do
      {:error, Error.new(:msg_invalid, "unsupported ack status")}
    else
      case MessageStore.get_by_msg_id(ctx.app_key, ack.msg_id) do
        {:ok, body} ->
          down = %MsgAck{
            msg_id: ack.msg_id,
            client_msg_id: ack.client_msg_id,
            status: :ACK_CLIENT_RECEIVED,
            conv_seq: ack.conv_seq || body.conv_seq
          }

          MsgTelemetry.ack_latency(:ack_up_processing, start, body.msg_type || :none, body.chat_type)

          if is_integer(body.server_time) and body.server_time > 0 do
            elapsed = max(System.system_time(:millisecond) - body.server_time, 0)
            MsgTelemetry.ack_latency_ms(:send_to_client_ack, elapsed, body.msg_type || :none, body.chat_type)
          end

          {:ok, %{ack_down: down, sender_user_id: body.from_uid, ack_from: ctx.user_id}}

        {:error, :not_found} ->
          {:error, Error.new(:msg_invalid, "msg not found")}
      end
    end
  end

  @doc """
  批量 ACK_UP → ACK_BATCH_DOWN 按发送方分组。

  ## 示例

      IM.Services.Message.ack_batch_up(batch, ctx)
  """
  @spec ack_batch_up(Pb.Im.Protocol.MsgAckBatchUp.t(), MessageContext.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def ack_batch_up(%Pb.Im.Protocol.MsgAckBatchUp{acks: acks}, %MessageContext{} = ctx)
      when is_list(acks) do
    results =
      Enum.reduce(acks, %{}, fn ack, acc ->
        case ack_up(ack, ctx) do
          {:ok, %{ack_down: down, sender_user_id: sender}} ->
            Map.update(acc, sender, [down], &[down | &1])

          _ ->
            acc
        end
      end)

    batches =
      Enum.map(results, fn {sender, downs} ->
        {sender, %Pb.Im.Protocol.MsgAckBatchDown{acks: Enum.reverse(downs)}}
      end)

    {:ok, %{batches: batches}}
  end

  defp client_received?(:ACK_CLIENT_RECEIVED), do: true
  defp client_received?(2), do: true
  defp client_received?(status) when is_atom(status), do: status == :ACK_CLIENT_RECEIVED
  defp client_received?(_), do: false

  defp validate_and_recipients(%ChatMessage{} = msg, %MessageContext{} = ctx) do
    case normalize_chat_type(msg.chat_type) do
      :CHAT_PRIVATE ->
        case validate_private(msg, ctx) do
          {:ok, normalized, recipients} -> {:ok, normalized, recipients, :write_fanout}
          err -> err
        end

      :CHAT_GROUP ->
        validate_group(msg, ctx)

      :CHAT_ROOM ->
        validate_room(msg, ctx)

      _ ->
        {:error, Error.new(:msg_invalid, "unsupported chat_type")}
    end
  end

  defp validate_private(%ChatMessage{} = msg, %MessageContext{} = ctx) do
    cond do
      msg.from != "" and msg.from != ctx.user_id ->
        {:error, Error.new(:msg_invalid, "from mismatch")}

      msg.to == "" ->
        {:error, Error.new(:msg_invalid, "to required")}

      true ->
        from = if msg.from == "", do: ctx.user_id, else: msg.from

        with :ok <- validate_burn(msg, :CHAT_PRIVATE),
             :ok <- Friend.check_send_permission(ctx.app_key, from, msg.to),
             msg_type = normalize_msg_type(msg.msg_type),
             {:ok, content} <- prepare_content(msg_type, msg.content),
             :ok <- maybe_track_stream(ctx.app_key, msg_type, content, from, msg.to),
             {:ok, conv_id} <- ConvId.normalize_private(msg.conv_id, from, msg.to) do
          normalized = %{
            msg
            | from: from,
              conv_id: conv_id,
              chat_type: :CHAT_PRIVATE,
              msg_type: msg_type,
              content: content,
              burn_after_read: msg.burn_after_read == true,
              burn_ttl_sec: clamp_burn_ttl(msg.burn_ttl_sec)
          }

          {:ok, normalized, [from, msg.to] |> Enum.uniq()}
        end
    end
  end

  defp validate_not_muted(app_key, group_id, user_id) do
    if IM.Permission.MuteCache.muted?(app_key, group_id, user_id) do
      {:error, Error.new(:group_no_permission, "muted in group")}
    else
      :ok
    end
  end

  defp validate_burn(%{burn_after_read: true}, chat_type) when chat_type != :CHAT_PRIVATE do
    {:error, Error.new(:msg_burn_denied, "burn only for private chat")}
  end

  defp validate_burn(%{burn_after_read: true}, :CHAT_PRIVATE) do
    if Application.get_env(:im, :burn_after_read_enabled, true) do
      :ok
    else
      {:error, Error.new(:msg_burn_denied, "burn disabled")}
    end
  end

  defp validate_burn(_, _), do: :ok

  defp clamp_burn_ttl(n) when is_integer(n) and n > 0 do
    max = Application.get_env(:im, :burn_ttl_sec_max, 3600)
    min(n, max)
  end

  defp clamp_burn_ttl(_), do: Application.get_env(:im, :burn_ttl_sec_default, 0)

  defp validate_group(%ChatMessage{} = msg, %MessageContext{} = ctx) do
    group_id = msg.to

    cond do
      msg.from != "" and msg.from != ctx.user_id ->
        {:error, Error.new(:msg_invalid, "from mismatch")}

      group_id == "" ->
        {:error, Error.new(:msg_invalid, "to(group_id) required")}

      true ->
        from = if msg.from == "", do: ctx.user_id, else: msg.from

        with :ok <- validate_burn(msg, :CHAT_GROUP),
             {:ok, conv_id} <- ConvId.normalize_group(msg.conv_id, group_id),
             {:ok, group} <- fetch_group(ctx.app_key, group_id),
             true <- MemberCache.member?(ctx.app_key, group_id, from) || :not_member,
             :ok <- validate_not_muted(ctx.app_key, group_id, from),
             msg_type = normalize_msg_type(msg.msg_type),
             {:ok, content} <- prepare_content(msg_type, msg.content),
             :ok <- maybe_track_stream(ctx.app_key, msg_type, content, from, group_id) do
          members = MemberCache.list_member_ids(ctx.app_key, group_id)
          recipients = resolve_group_recipients(from, members, msg.target_users)
          mode = FanoutPolicy.storage_mode(group)

          normalized = %{
            msg
            | from: from,
              to: group_id,
              conv_id: conv_id,
              chat_type: :CHAT_GROUP,
              msg_type: msg_type,
              content: content,
              target_users: targeted_list(msg.target_users)
          }

          {:ok, normalized, recipients, mode}
        else
          {:error, :not_found} ->
            {:error, Error.new(:group_not_found, "group not found")}

          :not_member ->
            {:error, Error.new(:group_not_member, "not a group member")}

          false ->
            {:error, Error.new(:group_not_member, "not a group member")}

          {:error, %Error{}} = err ->
            err
        end
    end
  end

  defp validate_room(%ChatMessage{} = msg, %MessageContext{} = ctx) do
    room_id = msg.to

    cond do
      msg.from != "" and msg.from != ctx.user_id ->
        {:error, Error.new(:msg_invalid, "from mismatch")}

      room_id == "" ->
        {:error, Error.new(:msg_invalid, "to(room_id) required")}

      true ->
        from = if msg.from == "", do: ctx.user_id, else: msg.from

        with {:ok, conv_id} <- ConvId.normalize_room(msg.conv_id, room_id),
             {:ok, room} <- fetch_room(ctx.app_key, room_id),
             true <- RoomMemberCache.member?(ctx.app_key, room_id, from) || :not_member do
          mode = if room.persist_msg, do: :room_persist, else: :room_ephemeral

          normalized = %{
            msg
            | from: from,
              to: room_id,
              conv_id: conv_id,
              chat_type: :CHAT_ROOM,
              msg_type: normalize_msg_type(msg.msg_type),
              target_users: targeted_list(msg.target_users)
          }

          # 聊天室不写 inbox；recipient 列表空
          {:ok, normalized, [], mode}
        else
          {:error, :not_found} ->
            {:error, Error.new(:msg_invalid, "room not found")}

          :not_member ->
            {:error, Error.new(:msg_invalid, "not a room member")}

          false ->
            {:error, Error.new(:msg_invalid, "not a room member")}

          {:error, %Error{}} = err ->
            err
        end
    end
  end

  defp fetch_group(app_key, group_id) do
    case MetaCache.get(app_key, group_id) do
      {:ok, _} = ok -> ok
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp fetch_room(app_key, room_id) do
    case RoomMetaCache.get(app_key, room_id) do
      {:ok, _} = ok -> ok
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp persist_new(%ChatMessage{} = msg, %MessageContext{} = ctx, recipients, storage_mode) do
    app_key = ctx.app_key
    client_msg_id = empty_to_nil(msg.client_msg_id)

    duplicate? =
      client_msg_id &&
        storage_mode not in [:room_ephemeral] &&
        case ClientMsgIdCache.lookup(app_key, msg.from, client_msg_id) do
          {:ok, msg_id} ->
            case MessageStore.get_by_msg_id(app_key, msg_id) do
              {:ok, body} -> {:ok, body}
              _ -> :miss
            end

          :miss ->
            case MessageStore.get_by_client_msg_id(app_key, msg.from, client_msg_id) do
              {:ok, body} ->
                :ok = ClientMsgIdCache.put(app_key, msg.from, client_msg_id, body.msg_id)
                {:ok, body}

              _ ->
                :miss
            end
        end

    case duplicate? do
      {:ok, body} ->
        {:ok, %{message: body_to_chat(body, msg), duplicate?: true, inbox_seqs: %{}}}

      _ ->
        allocate_and_insert(msg, ctx, client_msg_id, recipients, storage_mode)
    end
  end

  defp allocate_and_insert(msg, ctx, client_msg_id, recipients, storage_mode) do
    app_key = ctx.app_key
    msg_id = MsgId.next(app_key)
    conv_seq = Sequence.next(app_key, "conv_seq", msg.conv_id)
    server_time = System.system_time(:millisecond)

    attrs = %{
      app_key: app_key,
      msg_id: msg_id,
      chat_type: chat_type_int(msg.chat_type),
      conv_id: msg.conv_id,
      from_uid: msg.from,
      to_id: msg.to,
      msg_type: msg_type_int(msg.msg_type),
      content: msg.content || <<>>,
      server_time: server_time,
      conv_seq: conv_seq,
      client_msg_id: client_msg_id,
      target_users: empty_targets_to_nil(msg.target_users),
      burn_after_read: msg.burn_after_read == true,
      burn_ttl_sec: msg.burn_ttl_sec || 0
    }

    result =
      case storage_mode do
        :room_ephemeral ->
          chat = %{
            msg
            | msg_id: msg_id,
              server_time: server_time,
              conv_seq: conv_seq,
              client_msg_id: client_msg_id || ""
          }

          {:ok, %{message: chat, duplicate?: false, inbox_seqs: %{}}}

        :room_persist ->
          MessageStore.insert_body_only(attrs)

        :read_fanout ->
          MessageStore.insert_body_only(attrs)

        :write_fanout ->
          async? =
            msg.chat_type == :CHAT_GROUP and
              Application.get_env(:im, :group_inbox_fanout_async, false)

          if async? do
            with {:ok, r} <- MessageStore.insert_with_inbox(attrs, [msg.from]) do
              rest = Enum.reject(recipients, &(&1 == msg.from))
              if rest != [], do: GroupInboxFanout.enqueue(attrs, rest)
              {:ok, r}
            end
          else
            MessageStore.insert_with_inbox(attrs, recipients)
          end
      end

    case result do
      {:ok, %{message: chat, duplicate?: dup?, inbox_seqs: seqs}} ->
        maybe_cache_client_msg_id(app_key, msg.from, client_msg_id, chat.msg_id, dup?)
        unless dup?, do: bump_unreads(chat, ctx, recipients, storage_mode)
        {:ok, %{message: chat, duplicate?: dup?, inbox_seqs: seqs}}

      {:ok, %{body: body, inbox: inbox, duplicate?: dup?}} ->
        inbox_seqs = Map.new(inbox, fn row -> {row.user_id, row.inbox_seq} end)
        chat = body_to_chat(body, msg)
        maybe_cache_client_msg_id(app_key, msg.from, client_msg_id, body.msg_id, dup?)
        unless dup?, do: bump_unreads(chat, ctx, recipients, storage_mode)
        {:ok, %{message: chat, duplicate?: dup?, inbox_seqs: inbox_seqs}}

      {:error, %Error{code: :msg_invalid, msg: "duplicate client_msg_id"}} ->
        case MessageStore.get_by_client_msg_id(app_key, msg.from, client_msg_id) do
          {:ok, body} ->
            :ok = ClientMsgIdCache.put(app_key, msg.from, client_msg_id, body.msg_id)
            {:ok, %{message: body_to_chat(body, msg), duplicate?: true, inbox_seqs: %{}}}

          _ ->
            {:error, Error.new(:internal_error, "duplicate client_msg_id race")}
        end

      {:error, _} = err ->
        err
    end
  end

  defp bump_unreads(_msg, _ctx, _recipients, mode)
       when mode in [:room_ephemeral, :room_persist],
       do: :ok

  defp bump_unreads(%ChatMessage{} = msg, %MessageContext{} = ctx, recipients, _mode) do
    chat_type = chat_type_int(msg.chat_type)

    peer =
      case msg.chat_type do
        :CHAT_PRIVATE -> msg.from
        _ -> msg.to
      end

    opts = [
      chat_type: chat_type,
      peer_id: peer,
      msg_id: msg.msg_id,
      server_time: msg.server_time,
      conv_seq: msg.conv_seq,
      msg_type: msg_type_int(msg.msg_type),
      content: msg.content
    ]

    sender_peer =
      case msg.chat_type do
        :CHAT_PRIVATE -> msg.to
        _ -> msg.to
      end

    sender_opts = Keyword.put(opts, :peer_id, sender_peer)
    :ok = ConversationStore.touch_sender_conv(ctx.app_key, msg.from, msg.conv_id, sender_opts)

    recipients
    |> Enum.reject(&(&1 == msg.from))
    |> then(&ConversationStore.bump_unread_many(ctx.app_key, &1, msg.conv_id, opts))
  end

  defp maybe_cache_client_msg_id(_app, _from, cid, _msg_id, _dup?) when cid in [nil, ""], do: :ok
  defp maybe_cache_client_msg_id(_app, _from, _cid, _msg_id, true), do: :ok

  defp maybe_cache_client_msg_id(app_key, from, client_msg_id, msg_id, false) do
    ClientMsgIdCache.put(app_key, from, client_msg_id, msg_id)
  end

  defp body_to_chat(body, original) do
    %ChatMessage{
      msg_id: body.msg_id,
      client_msg_id: body.client_msg_id || "",
      chat_type: original.chat_type,
      from: body.from_uid,
      to: body.to_id,
      conv_id: body.conv_id,
      msg_type: original.msg_type,
      content: body.content,
      server_time: body.server_time,
      conv_seq: body.conv_seq,
      priority: original.priority,
      recalled: body.recalled,
      edit_version: body.edit_version,
      burn_after_read: body.burn_after_read,
      burn_ttl_sec: body.burn_ttl_sec || 0,
      burned: body.burned
    }
  end

  defp chat_type_int(:CHAT_PRIVATE), do: 1
  defp chat_type_int(:CHAT_GROUP), do: 2
  defp chat_type_int(:CHAT_ROOM), do: 3
  defp chat_type_int(n) when is_integer(n), do: n
  defp chat_type_int(_), do: 1

  defp resolve_group_recipients(from, members, target_users) do
    case targeted_list(target_users) do
      [] ->
        members

      targets ->
        allowed = MapSet.new(members)

        targets
        |> Enum.filter(&MapSet.member?(allowed, &1))
        |> then(&[from | &1])
        |> Enum.uniq()
    end
  end

  defp targeted_list(nil), do: []
  defp targeted_list([]), do: []
  defp targeted_list(list) when is_list(list), do: Enum.map(list, &to_string/1) |> Enum.reject(&(&1 == ""))
  defp targeted_list(_), do: []

  defp empty_targets_to_nil(targets) do
    case targeted_list(targets) do
      [] -> nil
      list -> list
    end
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(v), do: v

  defp normalize_chat_type(:CHAT_PRIVATE), do: :CHAT_PRIVATE
  defp normalize_chat_type(:CHAT_GROUP), do: :CHAT_GROUP
  defp normalize_chat_type(:CHAT_ROOM), do: :CHAT_ROOM
  defp normalize_chat_type(1), do: :CHAT_PRIVATE
  defp normalize_chat_type(2), do: :CHAT_GROUP
  defp normalize_chat_type(3), do: :CHAT_ROOM
  defp normalize_chat_type(v) when is_atom(v), do: v

  defp normalize_chat_type(v) when is_integer(v) do
    case ChatType.key(v) do
      atom when is_atom(atom) -> atom
      _ -> :CHAT_TYPE_UNSPECIFIED
    end
  end

  defp normalize_msg_type(v) when is_atom(v), do: v

  defp normalize_msg_type(v) when is_integer(v) do
    case MsgType.key(v) do
      atom when is_atom(atom) -> atom
      _ -> :MSG_TEXT
    end
  end

  defp normalize_msg_type(_), do: :MSG_TEXT

  defp prepare_content(:MSG_STREAM, content) when is_binary(content) do
    try do
      sc = StreamContent.decode(content)

      cond do
        sc.stream_id in [nil, ""] ->
          {:error, Error.new(:msg_invalid, "stream_id required")}

        sc.sequence < 0 ->
          {:error, Error.new(:msg_invalid, "invalid stream sequence")}

        true ->
          {:ok, content}
      end
    rescue
      _ -> {:error, Error.new(:msg_invalid, "invalid StreamContent")}
    end
  end

  defp prepare_content(_msg_type, content) when is_binary(content), do: {:ok, content}
  defp prepare_content(_msg_type, nil), do: {:ok, <<>>}
  defp prepare_content(_msg_type, other), do: {:ok, to_string(other)}

  defp maybe_track_stream(app_key, :MSG_STREAM, content, from, to) do
    sc = StreamContent.decode(content)

    StreamManager.track_chunk(app_key, sc, %{from: from, to: to})
  end

  defp maybe_track_stream(_app_key, _msg_type, _content, _from, _to), do: :ok

  defp msg_type_int(:MSG_TEXT), do: 1
  defp msg_type_int(n) when is_integer(n), do: n

  defp msg_type_int(atom) when is_atom(atom) do
    try do
      MsgType.value(atom)
    rescue
      FunctionClauseError -> 1
    end
  end

  defp msg_type_int(_), do: 1
end
