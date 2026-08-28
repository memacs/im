defmodule IM.Protocol.ReplyTest do
  use ExUnit.Case, async: true

  alias IM.Domain.Error
  alias IM.Protocol.Reply
  alias Pb.Im.Protocol.{CmdType, ErrorBody, ErrorCode, HeartbeatResp, Packet}

  defp request do
    %Packet{
      ver: 1,
      cmd: CmdType.value(:CMD_HEARTBEAT_REQ),
      seq: 99,
      cid: "req-cid",
      trace_id: "trace-hb",
      route_key: "u_1"
    }
  end

  describe "ok/3 与 success/3" do
    test "成功响应回传 seq / trace_id / cid，并使用指定 cmd" do
      payload = %HeartbeatResp{server_time: 123}

      assert {:ok, resp} = Reply.ok(request(), :CMD_HEARTBEAT_RESP, payload)
      assert resp.ver == 1
      assert resp.cmd == CmdType.value(:CMD_HEARTBEAT_RESP)
      assert resp.seq == 99
      assert resp.trace_id == "trace-hb"
      assert resp.cid == "req-cid"
      assert HeartbeatResp.decode(resp.payload).server_time == 123

      assert {:ok, same} = Reply.success(request(), :CMD_HEARTBEAT_RESP, payload)
      assert same.cmd == resp.cmd
      assert same.seq == resp.seq
    end
  end

  describe "error/2" do
    test "构造 CMD_ERROR，ErrorBody 含 ref_cmd 与 ref_cid" do
      err =
        Error.new(:unauthorized, "bad token",
          ref_cmd: CmdType.value(:CMD_AUTH_REQ),
          ref_cid: "auth-cid"
        )

      assert {:ok, packet} = Reply.error(request(), err)
      assert packet.cmd == CmdType.value(:CMD_ERROR)
      assert packet.seq == 99
      assert packet.trace_id == "trace-hb"

      body = ErrorBody.decode(packet.payload)
      assert body.code == :CODE_UNAUTHORIZED
      assert body.msg == "bad token"
      assert body.ref_cmd == CmdType.value(:CMD_AUTH_REQ)
      assert body.ref_cid == "auth-cid"
      assert ErrorCode.value(body.code) == 1001
    end

    test "未显式 ref_cid 时回退请求 cid" do
      err = Error.new(:msg_invalid, "bad", ref_cmd: 100)
      assert {:ok, packet} = Reply.error(request(), err)
      assert ErrorBody.decode(packet.payload).ref_cid == "req-cid"
    end
  end
end
