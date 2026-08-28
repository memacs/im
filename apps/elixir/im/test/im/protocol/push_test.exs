defmodule IM.Protocol.PushTest do
  use ExUnit.Case, async: true

  alias IM.Protocol.Push
  alias Pb.Im.Protocol.{ChatMessage, CmdType, MsgPushBatch, Packet}

  describe "build/3" do
    test "CMD_MSG_PUSH 的 seq 为 0，ver 为 1" do
      msg = %ChatMessage{msg_id: "m1", from: "a", to: "b"}

      assert {:ok, %Packet{} = packet} =
               Push.build(:CMD_MSG_PUSH, msg,
                 trace_id: "root-tr",
                 route_key: "g:1",
                 cid: "push-cid"
               )

      assert packet.ver == 1
      assert packet.cmd == CmdType.value(:CMD_MSG_PUSH)
      assert packet.seq == 0
      assert packet.trace_id == "root-tr"
      assert packet.route_key == "g:1"
      assert packet.cid == "push-cid"
      assert packet.ts > 0
      assert ChatMessage.decode(packet.payload).msg_id == "m1"
    end

    test "CMD_MSG_PUSH_BATCH 信封字段正确" do
      batch = %MsgPushBatch{messages: [%ChatMessage{msg_id: "m2"}]}

      assert {:ok, packet} = Push.build(CmdType.value(:CMD_MSG_PUSH_BATCH), batch, trace_id: "t")
      assert packet.cmd == CmdType.value(:CMD_MSG_PUSH_BATCH)
      assert packet.seq == 0
      assert packet.trace_id == "t"
    end
  end
end
