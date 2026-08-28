defmodule IM.WebSocket.HandlerAuthTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Protocol.Codec
  alias IM.WebSocket.{ConnectionState, Handler}
  alias Pb.Im.Protocol.{AuthReq, CmdType, HeartbeatReq, Packet}

  test "AUTH 成功后可心跳" do
    %{token: token, app_key: app_key, user_id: user_id, device_id: device_id} = AuthFixtures.login!()

    auth_payload =
      AuthReq.encode(%AuthReq{
        app_key: app_key,
        user_id: user_id,
        token: token,
        device_id: device_id,
        platform: "ios",
        sdk_ver: "1.0"
      })

    auth_packet = %Packet{
      ver: 1,
      cmd: CmdType.value(:CMD_AUTH_REQ),
      seq: 1,
      trace_id: "t-auth",
      payload: auth_payload
    }

    assert {:reply, auth_bin, state} = Handler.handle_packet(auth_packet, ConnectionState.new())
    assert {:ok, auth_out} = Codec.decode(auth_bin)
    assert auth_out.cmd == CmdType.value(:CMD_AUTH_RESP)
    assert state.status == :authenticated
    assert %DateTime{} = state.token_expires_at

    hb_packet = %Packet{
      ver: 1,
      cmd: CmdType.value(:CMD_HEARTBEAT_REQ),
      seq: 2,
      trace_id: "t-auth",
      payload: HeartbeatReq.encode(%HeartbeatReq{client_time: 1})
    }

    assert {:reply, hb_bin, state2} = Handler.handle_packet(hb_packet, state)
    assert {:ok, hb_out} = Codec.decode(hb_bin)
    assert hb_out.cmd == CmdType.value(:CMD_HEARTBEAT_RESP)
    assert hb_out.seq == 2
    assert state2.status == :authenticated
  end

  test "未鉴权发心跳静默关闭" do
    hb_packet = %Packet{
      ver: 1,
      cmd: CmdType.value(:CMD_HEARTBEAT_REQ),
      seq: 1,
      payload: HeartbeatReq.encode(%HeartbeatReq{})
    }

    assert {:stop, state} = Handler.handle_packet(hb_packet, ConnectionState.new())
    assert state.status == :closing
  end
end
