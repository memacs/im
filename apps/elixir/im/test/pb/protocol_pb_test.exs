defmodule Pb.ProtocolTest do
  @moduledoc """
  P0-04 验收：`proto/` 下的定义能生成并加载为可用的 Elixir message。

  这里只验证生成物本身可用（编解码、枚举值、前后兼容），
  业务语义留给各 service 的测试。
  """
  use ExUnit.Case, async: true

  alias Pb.Im.Protocol.{ChatMessage, CmdType, ErrorCode, Packet, PayloadCompression}

  describe "Packet 编解码" do
    test "全字段往返后与原值一致" do
      packet = %Packet{
        ver: 1,
        cmd: CmdType.value(:CMD_MSG_SEND),
        seq: 42,
        ts: 1_735_689_600_000,
        cid: "cid-abc",
        trace_id: "trace-xyz",
        payload: <<1, 2, 3>>,
        route_key: "u_1001",
        compression: :PAYLOAD_COMPRESSION_NONE
      }

      assert packet |> Packet.encode() |> Packet.decode() == packet
    end

    test "默认值字段不占字节（proto3 语义）" do
      assert Packet.encode(%Packet{}) == <<>>
      assert Packet.decode(<<>>) == %Packet{}
    end

    test "payload 是 bytes，由 cmd 决定内层类型" do
      inner = ChatMessage.encode(%ChatMessage{msg_id: "m_1", from: "u_1", to: "u_2"})

      decoded =
        %Packet{cmd: CmdType.value(:CMD_MSG_SEND), payload: inner}
        |> Packet.encode()
        |> Packet.decode()

      assert %ChatMessage{msg_id: "m_1", from: "u_1", to: "u_2"} =
               ChatMessage.decode(decoded.payload)
    end
  end

  describe "枚举值与 proto 定义对齐" do
    test "CmdType 区间约定未被改动" do
      assert CmdType.value(:CMD_AUTH_REQ) == 1
      assert CmdType.value(:CMD_MSG_SEND) == 100
      assert CmdType.value(:CMD_MSG_ACK_UP) == 200
      assert CmdType.value(:CMD_UNSPECIFIED) == 0
    end

    test "未知枚举数值原样保留，不会崩溃（新版客户端 → 老版服务端）" do
      packet = Packet.decode(Packet.encode(%Packet{cmd: 65_535}))
      assert packet.cmd == 65_535
    end

    test "ErrorCode 与 PayloadCompression 可用" do
      assert is_integer(ErrorCode.value(:CODE_PROTO_VERSION_UNSUPPORTED))
      assert PayloadCompression.value(:PAYLOAD_COMPRESSION_UNSPECIFIED) == 0
    end

    test "好友错误码段 7xxx 已生成" do
      assert ErrorCode.value(:CODE_FRIEND_SELF) == 7001
      assert ErrorCode.value(:CODE_FRIEND_BLOCKED_BY_PEER) == 7004
      assert ErrorCode.value(:CODE_FRIEND_NOT_FRIEND) == 7006
    end
  end

  describe "KickNotify / MsgRead 加固字段" do
    test "KickReason 枚举与 KickNotify.reason_code 可用" do
      alias Pb.Im.Protocol.{KickNotify, KickReason}

      notify = %KickNotify{
        reason: "device_banned",
        reason_code: :KICK_REASON_DEVICE_BANNED,
        timestamp: 1
      }

      assert notify |> KickNotify.encode() |> KickNotify.decode() == notify
      assert KickReason.value(:KICK_REASON_DUPLICATE_LOGIN) == 1
    end

    test "MsgRead.unread_count 为 optional，可区分未设置与 0" do
      alias Pb.Im.Protocol.MsgRead

      bare = MsgRead.decode(MsgRead.encode(%MsgRead{conv_id: "p:a:b"}))
      assert bare.unread_count == nil

      zero = MsgRead.decode(MsgRead.encode(%MsgRead{conv_id: "p:a:b", unread_count: 0}))
      assert zero.unread_count == 0
    end
  end

  describe "跨 package 生成" do
    test "im.event 与 im.protocol 各自成模块" do
      assert Code.ensure_loaded?(Pb.Im.Event.SessionEvent)
      assert Code.ensure_loaded?(Pb.Im.Protocol.AuthReq)
    end
  end
end
