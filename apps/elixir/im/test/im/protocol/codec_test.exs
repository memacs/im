defmodule IM.Protocol.CodecTest do
  use ExUnit.Case, async: true

  alias IM.Domain.Error
  alias IM.Protocol.Codec
  alias Pb.Im.Protocol.{ChatMessage, CmdType, Packet}

  describe "decode/1 与 encode/1" do
    test "合法 Packet 往返后关键字段一致" do
      original = %Packet{
        ver: 1,
        cmd: CmdType.value(:CMD_MSG_SEND),
        seq: 7,
        ts: 1_700_000_000_000,
        cid: "cid-1",
        trace_id: "tr-1",
        payload: <<9, 8, 7>>,
        route_key: "u_1",
        compression: :PAYLOAD_COMPRESSION_NONE
      }

      assert {:ok, bin} = Codec.encode(original)
      assert {:ok, decoded} = Codec.decode(bin)
      assert decoded == original
    end

    test "ver 不为 1 时返回 proto_version_unsupported" do
      bin = Packet.encode(%Packet{ver: 99, cmd: 1, seq: 1})
      assert {:error, %Error{code: :proto_version_unsupported}} = Codec.decode(bin)
    end

    test "ver 为 0（未指定）时返回 proto_version_unsupported" do
      bin = Packet.encode(%Packet{ver: 0, cmd: 1, seq: 1})
      assert {:error, %Error{code: :proto_version_unsupported}} = Codec.decode(bin)
    end

    test "损坏帧返回 msg_invalid 且不崩溃" do
      assert {:error, %Error{code: :msg_invalid}} = Codec.decode(<<0xFF, 0xFE, 0xFD>>)
    end
  end

  describe "encode_payload/1 与 decode_payload/2" do
    test "业务体可嵌入 Packet.payload 再解出" do
      msg = %ChatMessage{msg_id: "m1", from: "a", to: "b"}
      assert {:ok, bytes} = Codec.encode_payload(msg)

      packet = %Packet{ver: 1, cmd: CmdType.value(:CMD_MSG_SEND), payload: bytes}
      assert {:ok, encoded} = Codec.encode(packet)
      assert {:ok, decoded} = Codec.decode(encoded)
      assert decoded.payload == bytes

      assert {:ok, %ChatMessage{msg_id: "m1", from: "a", to: "b"}} =
               Codec.decode_payload(packet, ChatMessage)
    end
  end
end

