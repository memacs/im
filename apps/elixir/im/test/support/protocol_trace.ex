defmodule IM.ProtocolTrace do
  @moduledoc false

  alias IM.Client.Protocol.Codec
  alias Pb.Im.Protocol.CmdType

  @cmd_names %{
    1 => "CMD_AUTH_REQ",
    2 => "CMD_AUTH_RESP",
    3 => "CMD_HEARTBEAT_REQ",
    4 => "CMD_HEARTBEAT_RESP",
    5 => "CMD_KICK",
    6 => "CMD_ERROR",
    100 => "CMD_MSG_SEND",
    101 => "CMD_MSG_PUSH",
    200 => "CMD_MSG_ACK_UP",
    201 => "CMD_MSG_ACK_DOWN",
    202 => "CMD_MSG_READ",
    203 => "CMD_MSG_ACK_BATCH_UP",
    204 => "CMD_MSG_ACK_BATCH_DOWN",
    300 => "CMD_OFFLINE_PULL_REQ",
    301 => "CMD_OFFLINE_PULL_RESP",
    400 => "CMD_MSG_RECALL_REQ",
    401 => "CMD_MSG_RECALL_PUSH",
    402 => "CMD_MSG_EDIT_REQ",
    403 => "CMD_MSG_EDIT_PUSH",
    404 => "CMD_MSG_BURN_PUSH",
    500 => "CMD_PASSTHROUGH",
    600 => "CMD_GROUP_CREATE_REQ",
    601 => "CMD_GROUP_CREATE_RESP",
    603 => "CMD_GROUP_DISMISS_PUSH",
    605 => "CMD_GROUP_JOIN_PUSH",
    607 => "CMD_GROUP_LEAVE_PUSH",
    609 => "CMD_GROUP_KICK_PUSH",
    611 => "CMD_GROUP_INVITE_PUSH",
    613 => "CMD_GROUP_SET_ADMIN_PUSH",
    615 => "CMD_GROUP_REMOVE_ADMIN_PUSH",
    617 => "CMD_GROUP_TRANSFER_PUSH",
    619 => "CMD_GROUP_UPDATE_PUSH",
    701 => "CMD_ROOM_CREATE_RESP",
    703 => "CMD_ROOM_DISMISS_PUSH",
    705 => "CMD_ROOM_JOIN_PUSH",
    707 => "CMD_ROOM_LEAVE_PUSH",
    709 => "CMD_ROOM_KICK_PUSH",
    711 => "CMD_ROOM_UPDATE_PUSH",
    801 => "CMD_FRIEND_ADD_RESP",
    804 => "CMD_FRIEND_ACCEPT_RESP",
    807 => "CMD_FRIEND_REJECT_RESP",
    810 => "CMD_FRIEND_DELETE_RESP",
    813 => "CMD_FRIEND_BLOCK_RESP",
    816 => "CMD_FRIEND_UNBLOCK_RESP",
    818 => "CMD_FRIEND_SET_REMARK_RESP",
    820 => "CMD_FRIEND_LIST_RESP",
    822 => "CMD_FRIEND_REQUEST_LIST_RESP",
    901 => "CMD_CHANNEL_SUBSCRIBE_RESP",
    903 => "CMD_CHANNEL_UNSUBSCRIBE_RESP",
    904 => "CMD_CHANNEL_PUBLISH",
    905 => "CMD_CHANNEL_PUBLISH_ACK",
    906 => "CMD_CHANNEL_PUSH"
  }

  @cmd_payload_mods %{
    1 => Pb.Im.Protocol.AuthReq,
    2 => Pb.Im.Protocol.AuthResp,
    3 => Pb.Im.Protocol.HeartbeatReq,
    4 => Pb.Im.Protocol.HeartbeatResp,
    5 => Pb.Im.Protocol.KickNotify,
    6 => Pb.Im.Protocol.ErrorBody,
    100 => Pb.Im.Protocol.MsgSendReq,
    101 => Pb.Im.Protocol.ChatMessage,
    200 => Pb.Im.Protocol.MsgAck,
    201 => Pb.Im.Protocol.MsgAck,
    202 => Pb.Im.Protocol.MsgRead,
    203 => Pb.Im.Protocol.MsgAckBatchUp,
    300 => Pb.Im.Protocol.OfflinePullReq,
    301 => Pb.Im.Protocol.OfflinePullResp,
    400 => Pb.Im.Protocol.MsgRecall,
    401 => Pb.Im.Protocol.MsgRecall,
    402 => Pb.Im.Protocol.MsgEdit,
    403 => Pb.Im.Protocol.MsgEdit,
    404 => Pb.Im.Protocol.MsgBurn,
    500 => Pb.Im.Protocol.Passthrough,
    601 => Pb.Im.Protocol.GroupCreateResp,
    603 => Pb.Im.Protocol.GroupOperatePush,
    605 => Pb.Im.Protocol.GroupMemberPush,
    607 => Pb.Im.Protocol.GroupMemberPush,
    609 => Pb.Im.Protocol.GroupMemberPush,
    611 => Pb.Im.Protocol.GroupMemberPush,
    613 => Pb.Im.Protocol.GroupAdminPush,
    615 => Pb.Im.Protocol.GroupAdminPush,
    617 => Pb.Im.Protocol.GroupTransferPush,
    619 => Pb.Im.Protocol.GroupUpdatePush,
    701 => Pb.Im.Protocol.RoomCreateResp,
    703 => Pb.Im.Protocol.RoomOperatePush,
    705 => Pb.Im.Protocol.RoomMemberPush,
    707 => Pb.Im.Protocol.RoomMemberPush,
    709 => Pb.Im.Protocol.RoomMemberPush,
    711 => Pb.Im.Protocol.RoomUpdatePush,
    801 => Pb.Im.Protocol.FriendAddResp,
    804 => Pb.Im.Protocol.FriendAcceptResp,
    807 => Pb.Im.Protocol.FriendRejectResp,
    810 => Pb.Im.Protocol.FriendDeleteResp,
    813 => Pb.Im.Protocol.FriendBlockResp,
    816 => Pb.Im.Protocol.FriendUnblockResp,
    818 => Pb.Im.Protocol.FriendSetRemarkResp,
    820 => Pb.Im.Protocol.FriendListResp,
    822 => Pb.Im.Protocol.FriendRequestListResp,
    901 => Pb.Im.Protocol.ChannelSubscribeResp,
    903 => Pb.Im.Protocol.ChannelUnsubscribeResp,
    904 => Pb.Im.Protocol.ChannelPublish,
    905 => Pb.Im.Protocol.ChannelPublishAck,
    906 => Pb.Im.Protocol.ChannelPush
  }

  @doc false
  def new, do: Agent.start_link(fn -> [] end)

  @doc false
  def record(agent, meta, %Pb.Im.Protocol.Packet{} = packet) do
    entry = %{
      "step" => meta[:step],
      "case" => meta[:case],
      "actor" => meta[:actor],
      "direction" => meta[:direction],
      "note" => meta[:note],
      "packet" => packet_to_map(packet)
    }

    Agent.update(agent, fn acc -> acc ++ [entry] end)
    :ok
  end

  @doc false
  def record_body(agent, meta, body) when is_map(body) or is_struct(body) do
    entry = %{
      "step" => meta[:step],
      "case" => meta[:case],
      "actor" => meta[:actor],
      "direction" => meta[:direction],
      "note" => meta[:note],
      "payload" => struct_to_json(body)
    }

    Agent.update(agent, fn acc -> acc ++ [entry] end)
    :ok
  end

  @doc false
  def record_http(agent, meta, request, response) do
    entry =
      meta
      |> Map.take([:step, :case, :actor, :direction, :note])
      |> Map.merge(%{
        "http" => %{
          "request" => request,
          "response" => sanitize_response(response)
        }
      })

    Agent.update(agent, fn acc -> acc ++ [entry] end)
    :ok
  end

  @doc false
  def dump!(agent, path) do
    traces = Agent.get(agent, & &1)
    json = Jason.encode!(traces, pretty: true)
    File.write!(path, json)
    path
  end

  @doc false
  def cmd_name(cmd) when is_integer(cmd), do: Map.get(@cmd_names, cmd, "CMD_#{cmd}")

  @doc false
  def to_map(%Pb.Im.Protocol.Packet{} = packet), do: packet_to_map(packet)

  @doc false
  def uplink_packet(struct, seq \\ nil) do
    cmd = payload_cmd(struct)
    {:ok, body} = Codec.encode_payload(struct)

    %Pb.Im.Protocol.Packet{
      ver: 1,
      cmd: cmd,
      seq: seq || 0,
      ts: System.system_time(:millisecond),
      payload: body
    }
  end

  @doc false
  def payload_cmd(%Pb.Im.Protocol.AuthReq{}), do: CmdType.value(:CMD_AUTH_REQ)
  def payload_cmd(%Pb.Im.Protocol.HeartbeatReq{}), do: CmdType.value(:CMD_HEARTBEAT_REQ)
  def payload_cmd(%Pb.Im.Protocol.MsgSendReq{}), do: CmdType.value(:CMD_MSG_SEND)
  def payload_cmd(%Pb.Im.Protocol.MsgAck{}), do: CmdType.value(:CMD_MSG_ACK_UP)
  def payload_cmd(%Pb.Im.Protocol.MsgAckBatchUp{}), do: CmdType.value(:CMD_MSG_ACK_BATCH_UP)
  def payload_cmd(%Pb.Im.Protocol.OfflinePullReq{}), do: CmdType.value(:CMD_OFFLINE_PULL_REQ)
  def payload_cmd(%Pb.Im.Protocol.MsgRead{}), do: CmdType.value(:CMD_MSG_READ)
  def payload_cmd(%Pb.Im.Protocol.FriendSetRemarkReq{}), do: CmdType.value(:CMD_FRIEND_SET_REMARK_REQ)
  def payload_cmd(%Pb.Im.Protocol.FriendRequestListReq{}), do: CmdType.value(:CMD_FRIEND_REQUEST_LIST_REQ)
  def payload_cmd(%Pb.Im.Protocol.GroupTransferReq{}), do: CmdType.value(:CMD_GROUP_TRANSFER_REQ)
  def payload_cmd(%Pb.Im.Protocol.GroupUpdateReq{}), do: CmdType.value(:CMD_GROUP_UPDATE_REQ)
  def payload_cmd(%Pb.Im.Protocol.RoomUpdateReq{}), do: CmdType.value(:CMD_ROOM_UPDATE_REQ)
  def payload_cmd(%Pb.Im.Protocol.RoomKickReq{}), do: CmdType.value(:CMD_ROOM_KICK_REQ)
  def payload_cmd(%Pb.Im.Protocol.RoomOperateReq{}), do: CmdType.value(:CMD_ROOM_DISMISS_REQ)
  def payload_cmd(%Pb.Im.Protocol.ChannelUnsubscribeReq{}), do: CmdType.value(:CMD_CHANNEL_UNSUBSCRIBE_REQ)
  def payload_cmd(%Pb.Im.Protocol.ChannelPublish{}), do: CmdType.value(:CMD_CHANNEL_PUBLISH)
  def payload_cmd(_), do: 0

  defp packet_to_map(%Pb.Im.Protocol.Packet{} = packet) do
    base = %{
      "ver" => packet.ver,
      "cmd" => packet.cmd,
      "cmd_name" => cmd_name(packet.cmd),
      "seq" => packet.seq,
      "ts" => packet.ts,
      "cid" => packet.cid,
      "trace_id" => packet.trace_id,
      "route_key" => packet.route_key,
      "compression" => atom_name(packet.compression)
    }

    case Map.get(@cmd_payload_mods, packet.cmd) do
      nil ->
        Map.put(base, "payload_raw_bytes", byte_size(packet.payload || <<>>))

      mod ->
        case Codec.decode_payload(packet, mod) do
          {:ok, body} ->
            payload = maybe_expand_stream_content(body)
            Map.put(base, "payload", struct_to_json(payload))

          {:error, _} ->
            Map.put(base, "payload_decode_error", true)
        end
    end
  end

  defp maybe_expand_stream_content(%Pb.Im.Protocol.ChatMessage{msg_type: :MSG_STREAM, content: bin} = msg)
       when is_binary(bin) do
    case Pb.Im.Protocol.StreamContent.decode(bin) do
      %Pb.Im.Protocol.StreamContent{} = sc ->
        %{msg | content: struct_to_json(sc)}

      _ ->
        msg
    end
  end

  defp maybe_expand_stream_content(body), do: body

  defp struct_to_json(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {k, _v} -> k in [:__protobuf__, :__unknown_fields__] end)
    |> Map.new(fn {k, v} -> {Atom.to_string(k), encode_value(v)} end)
  end

  defp struct_to_json(other), do: encode_value(other)

  defp encode_value(list) when is_list(list), do: Enum.map(list, &encode_value/1)

  defp encode_value(%_{} = s), do: struct_to_json(s)

  defp encode_value(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), encode_value(v)} end)
  end

  defp encode_value(v) when is_nil(v), do: nil

  defp encode_value(v) when is_binary(v) do
    if String.valid?(v), do: v, else: Base.encode64(v)
  end

  defp encode_value(v) when is_atom(v), do: Atom.to_string(v)
  defp encode_value(v), do: v

  defp atom_name(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp atom_name(other), do: other

  defp sanitize_response(%Req.Response{} = resp) do
    %{
      "status" => resp.status,
      "body" => resp.body
    }
  end

  defp sanitize_response(other), do: other
end
