defmodule IM.Client.Connection do
  @moduledoc """
  WebSocket 连接 GenServer：状态机、seq 分配、Inbox 等待。

  状态：`:disconnected` → `:connecting` → `:connected` → `:authenticating` → `:authenticated`
  """

  use GenServer

  alias IM.Client.Error
  alias IM.Client.Protocol.Codec
  alias IM.Client.Transport

  alias Pb.Im.Protocol.{
    AuthReq,
    AuthResp,
    ChannelSubscribeReq,
    ChatMessage,
    CmdType,
    ErrorBody,
    FriendAcceptReq,
    FriendAddReq,
    FriendBlockReq,
    FriendDeleteReq,
    FriendListReq,
    FriendRejectReq,
    FriendUnblockReq,
    GroupAdminReq,
    GroupCreateReq,
    GroupInviteReq,
    GroupKickReq,
    GroupOperateReq,
    HeartbeatReq,
    MsgAck,
    MsgAckBatchUp,
    MsgEdit,
    MsgRead,
    MsgRecall,
    MsgSendReq,
    OfflinePullReq,
    Packet,
    Passthrough,
    RoomCreateReq,
    RoomOperateReq
  }

  @type status ::
          :disconnected
          | :connecting
          | :connected
          | :authenticating
          | :authenticated
          | :disconnecting

  defstruct [
    :url,
    :transport_mod,
    :transport_pid,
    status: :disconnected,
    seq: 0,
    inbox: [],
    waiters: %{},
    disconnect_waiter: nil
  ]

  @type t :: %__MODULE__{}

  # ── API ────────────────────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec connect(pid()) :: :ok | {:error, term()}
  def connect(pid), do: GenServer.call(pid, :connect, 15_000)

  @spec authenticate(pid(), map()) :: {:ok, map()} | {:error, term()}
  def authenticate(pid, attrs), do: GenServer.call(pid, {:authenticate, attrs}, 15_000)

  @spec heartbeat(pid(), keyword()) :: {:ok, Packet.t()} | {:error, term()}
  def heartbeat(pid, opts \\ []), do: GenServer.call(pid, {:heartbeat, opts}, 10_000)

  @spec send_message(pid(), map()) :: {:ok, Packet.t()} | {:error, term()}
  def send_message(pid, attrs), do: GenServer.call(pid, {:send_message, attrs}, 15_000)

  @spec subscribe_channels(pid(), [String.t()]) :: {:ok, Packet.t()} | {:error, term()}
  def subscribe_channels(pid, channel_ids) when is_list(channel_ids) do
    GenServer.call(pid, {:subscribe_channels, channel_ids}, 15_000)
  end

  @doc "发送任意已编码 payload 的命令并等待同 seq 响应。"
  @spec request(pid(), atom() | non_neg_integer(), struct(), keyword()) ::
          {:ok, Packet.t()} | {:error, term()}
  def request(pid, cmd, payload, opts \\ []) do
    GenServer.call(pid, {:request, cmd, payload, opts}, Keyword.get(opts, :timeout, 15_000))
  end

  @doc "发送无同 seq 响应的上行命令（如 ACK_UP / MSG_READ / PASSTHROUGH）。"
  @spec notify(pid(), atom() | non_neg_integer(), struct(), keyword()) :: :ok | {:error, term()}
  def notify(pid, cmd, payload, opts \\ []) do
    GenServer.call(pid, {:notify, cmd, payload, opts}, 10_000)
  end

  @spec ack_client_received(pid(), map()) :: :ok | {:error, term()}
  def ack_client_received(pid, attrs) do
    ack = %MsgAck{
      msg_id: fetch_str(attrs, :msg_id),
      client_msg_id: fetch_str(attrs, :client_msg_id),
      status: :ACK_CLIENT_RECEIVED,
      conv_seq: Map.get(attrs, :conv_seq, Map.get(attrs, "conv_seq", 0))
    }

    notify(pid, :CMD_MSG_ACK_UP, ack)
  end

  @spec offline_pull(pid(), map()) :: {:ok, Packet.t()} | {:error, term()}
  def offline_pull(pid, attrs \\ %{}) do
    req = %OfflinePullReq{
      conv_id: fetch_str(attrs, :conv_id),
      cursor: Map.get(attrs, :cursor, Map.get(attrs, "cursor", 0)),
      limit: Map.get(attrs, :limit, Map.get(attrs, "limit", 50))
    }

    request(pid, :CMD_OFFLINE_PULL_REQ, req)
  end

  @spec recall_message(pid(), map()) :: {:ok, Packet.t()} | {:error, term()}
  def recall_message(pid, attrs) do
    request(pid, :CMD_MSG_RECALL_REQ, %MsgRecall{
      msg_id: fetch_str(attrs, :msg_id),
      reason: fetch_str(attrs, :reason),
      conv_id: fetch_str(attrs, :conv_id)
    })
  end

  @spec edit_message(pid(), map()) :: {:ok, Packet.t()} | {:error, term()}
  def edit_message(pid, attrs) do
    content = Map.get(attrs, :content, Map.get(attrs, "content", ""))

    request(pid, :CMD_MSG_EDIT_REQ, %MsgEdit{
      msg_id: fetch_str(attrs, :msg_id),
      content: if(is_binary(content), do: content, else: to_string(content)),
      conv_id: fetch_str(attrs, :conv_id)
    })
  end

  @spec create_group(pid(), map()) :: {:ok, Packet.t()} | {:error, term()}
  def create_group(pid, attrs) do
    request(pid, :CMD_GROUP_CREATE_REQ, %GroupCreateReq{
      name: fetch_str(attrs, :name),
      group_id: fetch_str(attrs, :group_id),
      member_uids: list_str(attrs, :member_uids),
      announcement: fetch_str(attrs, :announcement)
    })
  end

  @spec join_group(pid(), String.t()) :: {:ok, Packet.t()} | {:error, term()}
  def join_group(pid, group_id) do
    request(pid, :CMD_GROUP_JOIN_REQ, %GroupOperateReq{group_id: group_id})
  end

  @spec leave_group(pid(), String.t()) :: {:ok, Packet.t()} | {:error, term()}
  def leave_group(pid, group_id) do
    request(pid, :CMD_GROUP_LEAVE_REQ, %GroupOperateReq{group_id: group_id})
  end

  @spec create_room(pid(), map()) :: {:ok, Packet.t()} | {:error, term()}
  def create_room(pid, attrs) do
    request(pid, :CMD_ROOM_CREATE_REQ, %RoomCreateReq{
      name: fetch_str(attrs, :name),
      room_id: fetch_str(attrs, :room_id)
    })
  end

  @spec join_room(pid(), String.t()) :: {:ok, Packet.t()} | {:error, term()}
  def join_room(pid, room_id) do
    request(pid, :CMD_ROOM_JOIN_REQ, %RoomOperateReq{room_id: room_id})
  end

  @spec leave_room(pid(), String.t()) :: {:ok, Packet.t()} | {:error, term()}
  def leave_room(pid, room_id) do
    request(pid, :CMD_ROOM_LEAVE_REQ, %RoomOperateReq{room_id: room_id})
  end

  @spec add_friend(pid(), map()) :: {:ok, Packet.t()} | {:error, term()}
  def add_friend(pid, attrs) do
    request(pid, :CMD_FRIEND_ADD_REQ, %FriendAddReq{
      to_user_id: fetch_str(attrs, :to_user_id),
      message: fetch_str(attrs, :message),
      remark: fetch_str(attrs, :remark)
    })
  end

  @spec accept_friend(pid(), map()) :: {:ok, Packet.t()} | {:error, term()}
  def accept_friend(pid, attrs) do
    request(pid, :CMD_FRIEND_ACCEPT_REQ, %FriendAcceptReq{
      request_id: fetch_str(attrs, :request_id),
      from_user_id: fetch_str(attrs, :from_user_id),
      remark: fetch_str(attrs, :remark)
    })
  end

  @spec reject_friend(pid(), map()) :: {:ok, Packet.t()} | {:error, term()}
  def reject_friend(pid, attrs) do
    request(pid, :CMD_FRIEND_REJECT_REQ, %FriendRejectReq{
      request_id: fetch_str(attrs, :request_id),
      from_user_id: fetch_str(attrs, :from_user_id)
    })
  end

  @spec delete_friend(pid(), String.t() | map()) :: {:ok, Packet.t()} | {:error, term()}
  def delete_friend(pid, friend_user_id) when is_binary(friend_user_id) do
    delete_friend(pid, %{friend_user_id: friend_user_id})
  end

  def delete_friend(pid, attrs) when is_map(attrs) do
    request(pid, :CMD_FRIEND_DELETE_REQ, %FriendDeleteReq{
      friend_user_id: fetch_str(attrs, :friend_user_id)
    })
  end

  @spec block_friend(pid(), String.t() | map()) :: {:ok, Packet.t()} | {:error, term()}
  def block_friend(pid, user_id) when is_binary(user_id) do
    block_friend(pid, %{user_id: user_id})
  end

  def block_friend(pid, attrs) when is_map(attrs) do
    request(pid, :CMD_FRIEND_BLOCK_REQ, %FriendBlockReq{user_id: fetch_str(attrs, :user_id)})
  end

  @spec unblock_friend(pid(), String.t() | map()) :: {:ok, Packet.t()} | {:error, term()}
  def unblock_friend(pid, user_id) when is_binary(user_id) do
    unblock_friend(pid, %{user_id: user_id})
  end

  def unblock_friend(pid, attrs) when is_map(attrs) do
    request(pid, :CMD_FRIEND_UNBLOCK_REQ, %FriendUnblockReq{user_id: fetch_str(attrs, :user_id)})
  end

  @spec list_friends(pid()) :: {:ok, Packet.t()} | {:error, term()}
  def list_friends(pid), do: request(pid, :CMD_FRIEND_LIST_REQ, %FriendListReq{})

  @spec dismiss_group(pid(), String.t()) :: {:ok, Packet.t()} | {:error, term()}
  def dismiss_group(pid, group_id) when is_binary(group_id) do
    request(pid, :CMD_GROUP_DISMISS_REQ, %GroupOperateReq{group_id: group_id})
  end

  @spec kick_group_members(pid(), map()) :: {:ok, Packet.t()} | {:error, term()}
  def kick_group_members(pid, attrs) do
    request(pid, :CMD_GROUP_KICK_REQ, %GroupKickReq{
      group_id: fetch_str(attrs, :group_id),
      member_uids: list_str(attrs, :member_uids),
      reason: fetch_str(attrs, :reason)
    })
  end

  @spec invite_group_members(pid(), map()) :: {:ok, Packet.t()} | {:error, term()}
  def invite_group_members(pid, attrs) do
    request(pid, :CMD_GROUP_INVITE_REQ, %GroupInviteReq{
      group_id: fetch_str(attrs, :group_id),
      member_uids: list_str(attrs, :member_uids)
    })
  end

  @spec set_group_admin(pid(), map()) :: {:ok, Packet.t()} | {:error, term()}
  def set_group_admin(pid, attrs) do
    request(pid, :CMD_GROUP_SET_ADMIN_REQ, %GroupAdminReq{
      group_id: fetch_str(attrs, :group_id),
      member_uid: fetch_str(attrs, :member_uid)
    })
  end

  @spec remove_group_admin(pid(), map()) :: {:ok, Packet.t()} | {:error, term()}
  def remove_group_admin(pid, attrs) do
    request(pid, :CMD_GROUP_REMOVE_ADMIN_REQ, %GroupAdminReq{
      group_id: fetch_str(attrs, :group_id),
      member_uid: fetch_str(attrs, :member_uid)
    })
  end

  @spec ack_batch(pid(), [map()]) :: :ok | {:error, term()}
  def ack_batch(pid, acks) when is_list(acks) do
    encoded =
      Enum.map(acks, fn attrs ->
        %MsgAck{
          msg_id: fetch_str(attrs, :msg_id),
          client_msg_id: fetch_str(attrs, :client_msg_id),
          status: Map.get(attrs, :status, Map.get(attrs, "status", :ACK_CLIENT_RECEIVED)),
          conv_seq: Map.get(attrs, :conv_seq, Map.get(attrs, "conv_seq", 0))
        }
      end)

    notify(pid, :CMD_MSG_ACK_BATCH_UP, %MsgAckBatchUp{acks: encoded})
  end

  @spec msg_read(pid(), map()) :: :ok | {:error, term()}
  def msg_read(pid, attrs) do
    notify(pid, :CMD_MSG_READ, %MsgRead{
      chat_type: Map.get(attrs, :chat_type, Map.get(attrs, "chat_type", :CHAT_PRIVATE)),
      from: fetch_str(attrs, :from),
      to: fetch_str(attrs, :to),
      msg_id: fetch_str(attrs, :msg_id),
      conv_seq: Map.get(attrs, :conv_seq, Map.get(attrs, "conv_seq", 0)),
      timestamp: Map.get(attrs, :timestamp, Map.get(attrs, "timestamp", 0)),
      conv_id: fetch_str(attrs, :conv_id)
    })
  end

  @spec passthrough(pid(), map()) :: :ok | {:error, term()}
  def passthrough(pid, attrs) do
    data = Map.get(attrs, :data, Map.get(attrs, "data", <<>>))

    notify(pid, :CMD_PASSTHROUGH, %Passthrough{
      chat_type: Map.get(attrs, :chat_type, :CHAT_PRIVATE),
      from: fetch_str(attrs, :from),
      to: fetch_str(attrs, :to),
      action: fetch_str(attrs, :action),
      data: if(is_binary(data), do: data, else: to_string(data)),
      persist: Map.get(attrs, :persist, false) == true
    })
  end

  @spec disconnect(pid()) :: :ok
  def disconnect(pid), do: GenServer.call(pid, :disconnect, 5_000)

  @doc """
  发送任意已编码 payload 的命令（不等待响应）。

  用于未鉴权/重复鉴权等协议守卫 E2E；要求状态为 `:connected`、`:authenticating` 或 `:authenticated`。
  """
  @spec send_raw(pid(), keyword()) :: :ok | {:error, term()}
  def send_raw(pid, opts) when is_list(opts) do
    GenServer.call(pid, {:send_raw, opts}, 10_000)
  end

  @doc "等待传输层断开（服务端静默关连接等）。"
  @spec await_disconnected(pid(), timeout()) :: :ok | {:error, term()}
  def await_disconnected(pid, timeout \\ 5_000) do
    GenServer.call(pid, {:await_disconnected, timeout}, timeout + 1_000)
  end

  @spec await(pid(), keyword(), timeout()) :: {:ok, Packet.t()} | {:error, term()}
  def await(pid, matcher, timeout \\ 5_000) do
    GenServer.call(pid, {:await, matcher, timeout}, timeout + 1_000)
  end

  @spec status(pid()) :: status()
  def status(pid), do: GenServer.call(pid, :status)

  # ── GenServer ──────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    url = Keyword.fetch!(opts, :url)
    transport = Keyword.get(opts, :transport, Transport)

    {:ok, %__MODULE__{url: url, transport_mod: transport}}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  def handle_call(:connect, _from, %{status: :disconnected} = state) do
    case state.transport_mod.start_link(state.url, self(), []) do
      {:ok, tpid} ->
        {:reply, :ok, %{state | transport_pid: tpid, status: :connected}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:connect, _from, state) do
    {:reply, {:error, Error.new(:invalid_state, "status=#{state.status}")}, state}
  end

  def handle_call({:authenticate, attrs}, from, %{status: :connected} = state) do
    with {:ok, payload} <- build_auth_payload(attrs),
         {:ok, state2, seq} <- next_seq(state),
         packet = %Packet{
           ver: 1,
           cmd: CmdType.value(:CMD_AUTH_REQ),
           seq: seq,
           ts: now_ms(),
           trace_id: Map.get(attrs, :trace_id, Map.get(attrs, "trace_id", "")),
           payload: payload
         },
         {:ok, bin} <- Codec.encode(packet),
         :ok <- send_bin(state2, bin) do
      state3 = register_waiter(%{state2 | status: :authenticating}, {:seq, seq}, from, :auth)
      {:noreply, state3}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:authenticate, _}, _from, state) do
    {:reply, {:error, Error.new(:invalid_state, "status=#{state.status}")}, state}
  end

  def handle_call({:heartbeat, opts}, from, %{status: :authenticated} = state) do
    client_time = Keyword.get(opts, :client_time, now_ms())

    with {:ok, payload} <- Codec.encode_payload(%HeartbeatReq{client_time: client_time}),
         {:ok, state2, seq} <- next_seq(state),
         packet = %Packet{
           ver: 1,
           cmd: CmdType.value(:CMD_HEARTBEAT_REQ),
           seq: seq,
           ts: now_ms(),
           payload: payload
         },
         {:ok, bin} <- Codec.encode(packet),
         :ok <- send_bin(state2, bin) do
      {:noreply, register_waiter(state2, {:seq, seq}, from, :packet)}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:heartbeat, _}, _from, state) do
    {:reply, {:error, Error.new(:invalid_state, "status=#{state.status}")}, state}
  end

  def handle_call({:send_message, attrs}, from, %{status: :authenticated} = state) do
    with {:ok, payload} <- build_msg_payload(attrs),
         {:ok, state2, seq} <- next_seq(state),
         packet = %Packet{
           ver: 1,
           cmd: CmdType.value(:CMD_MSG_SEND),
           seq: seq,
           ts: now_ms(),
           cid: Map.get(attrs, :cid, Map.get(attrs, "cid", "")),
           trace_id: Map.get(attrs, :trace_id, Map.get(attrs, "trace_id", "")),
           route_key: Map.get(attrs, :route_key, Map.get(attrs, "route_key", "")),
           payload: payload
         },
         {:ok, bin} <- Codec.encode(packet),
         :ok <- send_bin(state2, bin) do
      {:noreply, register_waiter(state2, {:seq, seq}, from, :packet)}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send_message, _}, _from, state) do
    {:reply, {:error, Error.new(:invalid_state, "status=#{state.status}")}, state}
  end

  def handle_call({:subscribe_channels, ids}, from, %{status: :authenticated} = state) do
    with {:ok, payload} <- Codec.encode_payload(%ChannelSubscribeReq{channel_ids: ids}),
         {:ok, state2, seq} <- next_seq(state),
         packet = %Packet{
           ver: 1,
           cmd: CmdType.value(:CMD_CHANNEL_SUBSCRIBE_REQ),
           seq: seq,
           ts: now_ms(),
           payload: payload
         },
         {:ok, bin} <- Codec.encode(packet),
         :ok <- send_bin(state2, bin) do
      {:noreply, register_waiter(state2, {:seq, seq}, from, :packet)}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:subscribe_channels, _}, _from, state) do
    {:reply, {:error, Error.new(:invalid_state, "status=#{state.status}")}, state}
  end

  def handle_call({:request, cmd, payload, opts}, from, %{status: :authenticated} = state) do
    cmd_val = if is_atom(cmd), do: CmdType.value(cmd), else: cmd

    with {:ok, body} <- Codec.encode_payload(payload),
         {:ok, state2, seq} <- next_seq(state),
         packet = %Packet{
           ver: 1,
           cmd: cmd_val,
           seq: seq,
           ts: now_ms(),
           cid: Keyword.get(opts, :cid, ""),
           trace_id: Keyword.get(opts, :trace_id, ""),
           route_key: Keyword.get(opts, :route_key, ""),
           payload: body
         },
         {:ok, bin} <- Codec.encode(packet),
         :ok <- send_bin(state2, bin) do
      {:noreply, register_waiter(state2, {:seq, seq}, from, :packet)}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:request, _, _, _}, _from, state) do
    {:reply, {:error, Error.new(:invalid_state, "status=#{state.status}")}, state}
  end

  def handle_call({:notify, cmd, payload, opts}, _from, %{status: :authenticated} = state) do
    cmd_val = if is_atom(cmd), do: CmdType.value(cmd), else: cmd

    with {:ok, body} <- Codec.encode_payload(payload),
         {:ok, state2, seq} <- next_seq(state),
         packet = %Packet{
           ver: 1,
           cmd: cmd_val,
           seq: seq,
           ts: now_ms(),
           cid: Keyword.get(opts, :cid, ""),
           trace_id: Keyword.get(opts, :trace_id, ""),
           route_key: Keyword.get(opts, :route_key, ""),
           payload: body
         },
         {:ok, bin} <- Codec.encode(packet),
         :ok <- send_bin(state2, bin) do
      {:reply, :ok, state2}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:notify, _, _, _}, _from, state) do
    {:reply, {:error, Error.new(:invalid_state, "status=#{state.status}")}, state}
  end

  def handle_call({:send_raw, opts}, _from, %{status: status} = state)
      when status in [:connected, :authenticating, :authenticated] do
    cmd = Keyword.fetch!(opts, :cmd)
    payload = Keyword.fetch!(opts, :payload)
    cmd_val = if is_atom(cmd), do: CmdType.value(cmd), else: cmd

    with {:ok, body} <- Codec.encode_payload(payload),
         {:ok, state2, seq} <- next_seq(state),
         seq = Keyword.get(opts, :seq, seq),
         packet = %Packet{
           ver: 1,
           cmd: cmd_val,
           seq: seq,
           ts: now_ms(),
           cid: Keyword.get(opts, :cid, ""),
           trace_id: Keyword.get(opts, :trace_id, ""),
           payload: body
         },
         {:ok, bin} <- Codec.encode(packet),
         :ok <- send_bin(state2, bin) do
      {:reply, :ok, state2}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send_raw, _}, _from, state) do
    {:reply, {:error, Error.new(:invalid_state, "status=#{state.status}")}, state}
  end

  def handle_call(:disconnect, _from, state) do
    if state.transport_pid, do: state.transport_mod.close(state.transport_pid)
    reply_all_waiters(state, {:error, Error.new(:disconnected, "disconnect")})
    {:reply, :ok, %__MODULE__{url: state.url, transport_mod: state.transport_mod}}
  end

  def handle_call({:await, matcher, timeout}, from, state) do
    key = matcher_key(matcher)

    case take_inbox(state.inbox, key) do
      {:ok, packet, rest} ->
        {:reply, {:ok, packet}, %{state | inbox: rest}}

      :miss ->
        ref = Process.send_after(self(), {:await_timeout, key}, timeout)
        waiter = %{from: from, kind: :packet, timer: ref}
        {:noreply, %{state | waiters: Map.put(state.waiters, key, waiter)}}
    end
  end

  def handle_call({:await_disconnected, _timeout}, _from, %{status: :disconnected} = state) do
    {:reply, :ok, state}
  end

  def handle_call({:await_disconnected, timeout}, from, state) do
    ref = Process.send_after(self(), {:disconnect_wait_timeout, from}, timeout)
    {:noreply, %{state | disconnect_waiter: {from, ref}}}
  end

  @impl true
  def handle_info({:im_client_frame, bin}, state) when is_binary(bin) do
    case Codec.decode(bin) do
      {:ok, packet} ->
        {:noreply, dispatch_packet(state, packet)}

      {:error, _} ->
        {:noreply, state}
    end
  end

  def handle_info({:im_client_disconnected, _reason}, state) do
    reply_all_waiters(state, {:error, Error.new(:disconnected, "transport closed")})
    state = reply_disconnect_waiter(state)
    {:noreply, %{state | status: :disconnected, transport_pid: nil, waiters: %{}}}
  end

  def handle_info({:await_timeout, key}, state) do
    case Map.pop(state.waiters, key) do
      {nil, _} ->
        {:noreply, state}

      {%{from: from}, waiters} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | waiters: waiters}}
    end
  end

  def handle_info({:disconnect_wait_timeout, from}, state) do
    if match?({^from, _}, state.disconnect_waiter) do
      GenServer.reply(from, {:error, :timeout})
      {:noreply, %{state | disconnect_waiter: nil}}
    else
      {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  # ── 内部 ───────────────────────────────────────────────────────────────────

  defp dispatch_packet(state, %Packet{} = packet) do
    key = {:seq, packet.seq}

    case Map.pop(state.waiters, key) do
      {nil, _} ->
        # 也尝试按 cmd 等待
        cmd_key = {:cmd, packet.cmd}

        case Map.pop(state.waiters, cmd_key) do
          {nil, _} ->
            %{state | inbox: [packet | state.inbox]}

          {%{from: from, kind: kind, timer: timer}, waiters} ->
            cancel_timer(timer)
            GenServer.reply(from, reply_for(kind, packet))
            maybe_auth_ok(%{state | waiters: waiters}, packet, kind)
        end

      {%{from: from, kind: kind, timer: timer}, waiters} ->
        cancel_timer(timer)
        GenServer.reply(from, reply_for(kind, packet))
        maybe_auth_ok(%{state | waiters: waiters}, packet, kind)
    end
  end

  defp maybe_auth_ok(state, packet, :auth) do
    if packet.cmd == CmdType.value(:CMD_AUTH_RESP) do
      %{state | status: :authenticated}
    else
      %{state | status: :connected}
    end
  end

  defp maybe_auth_ok(state, _packet, _), do: state

  @auth_resp_cmd CmdType.value(:CMD_AUTH_RESP)
  @cmd_error CmdType.value(:CMD_ERROR)

  defp reply_for(:auth, %Packet{cmd: @auth_resp_cmd} = packet) do
    case Codec.decode_payload(packet, AuthResp) do
      {:ok, %AuthResp{} = resp} ->
        {:ok,
         %{
           packet: packet,
           server_time: resp.server_time,
           user_id: resp.user_id,
           heartbeat_interval_sec: resp.heartbeat_interval_sec
         }}

      {:error, err} ->
        {:error, err}
    end
  end

  defp reply_for(:auth, %Packet{cmd: @cmd_error} = packet) do
    case Codec.decode_payload(packet, ErrorBody) do
      {:ok, %ErrorBody{} = body} ->
        msg = body.msg || "auth rejected"

        {:error, Error.new(:auth_failed, msg, packet: packet)}

      {:error, err} ->
        {:error, err}
    end
  end

  defp reply_for(:auth, packet) do
    {:error, Error.new(:auth_failed, "unexpected cmd=#{packet.cmd}")}
  end

  defp reply_for(:packet, packet), do: {:ok, packet}

  defp register_waiter(state, key, from, kind) do
    ref = Process.send_after(self(), {:await_timeout, key}, 12_000)
    waiter = %{from: from, kind: kind, timer: ref}
    %{state | waiters: Map.put(state.waiters, key, waiter)}
  end

  defp reply_all_waiters(state, reply) do
    Enum.each(state.waiters, fn {_key, %{from: from, timer: timer}} ->
      cancel_timer(timer)
      GenServer.reply(from, reply)
    end)
  end

  defp reply_disconnect_waiter(%{disconnect_waiter: {from, ref}} = state) do
    cancel_timer(ref)
    GenServer.reply(from, :ok)
    %{state | disconnect_waiter: nil}
  end

  defp reply_disconnect_waiter(state), do: state

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  defp matcher_key(matcher) do
    cond do
      Keyword.has_key?(matcher, :seq) -> {:seq, Keyword.fetch!(matcher, :seq)}
      Keyword.has_key?(matcher, :cmd) -> {:cmd, Keyword.fetch!(matcher, :cmd)}
      true -> raise ArgumentError, "await matcher needs :seq or :cmd"
    end
  end

  defp take_inbox(inbox, key) do
    {hit, rest} =
      Enum.split_with(inbox, fn %Packet{} = p ->
        case key do
          {:seq, seq} -> p.seq == seq
          {:cmd, cmd} -> p.cmd == cmd
        end
      end)

    case hit do
      [packet | more] -> {:ok, packet, more ++ rest}
      [] -> :miss
    end
  end

  defp next_seq(state) do
    seq = state.seq + 1
    {:ok, %{state | seq: seq}, seq}
  end

  defp send_bin(%{transport_pid: nil}, _), do: {:error, Error.new(:not_connected, "no transport")}

  defp send_bin(state, bin) do
    state.transport_mod.send_binary(state.transport_pid, bin)
  end

  defp build_auth_payload(attrs) do
    req = %AuthReq{
      app_key: fetch_str(attrs, :app_key),
      user_id: fetch_str(attrs, :user_id),
      token: fetch_str(attrs, :token),
      device_id: fetch_str(attrs, :device_id),
      platform: fetch_str(attrs, :platform, "loadtest"),
      sdk_ver: fetch_str(attrs, :sdk_ver, "0.1.0")
    }

    Codec.encode_payload(req)
  end

  defp build_msg_payload(attrs) do
    content = Map.get(attrs, :content, Map.get(attrs, "content", "ping"))

    content_bin =
      cond do
        is_binary(content) -> content
        true -> to_string(content)
      end

    msg = %ChatMessage{
      from: fetch_str(attrs, :from, ""),
      to: fetch_str(attrs, :to),
      chat_type: Map.get(attrs, :chat_type, Map.get(attrs, "chat_type", :CHAT_PRIVATE)),
      msg_type: Map.get(attrs, :msg_type, Map.get(attrs, "msg_type", :MSG_TEXT)),
      content: content_bin,
      client_msg_id: fetch_str(attrs, :client_msg_id, generate_cid()),
      burn_after_read: Map.get(attrs, :burn_after_read, Map.get(attrs, "burn_after_read", false)) == true,
      burn_ttl_sec: Map.get(attrs, :burn_ttl_sec, Map.get(attrs, "burn_ttl_sec", 0))
    }

    Codec.encode_payload(%MsgSendReq{message: msg})
  end

  defp fetch_str(map, key, default \\ "") do
    case Map.get(map, key, Map.get(map, Atom.to_string(key), default)) do
      nil -> default
      v -> to_string(v)
    end
  end

  defp list_str(map, key) do
    raw = Map.get(map, key, Map.get(map, Atom.to_string(key), []))
    raw |> List.wrap() |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == ""))
  end

  defp generate_cid do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp now_ms, do: System.system_time(:millisecond)
end

