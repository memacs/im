defmodule IM.Cluster.FanoutBatcherTest do
  use ExUnit.Case, async: true

  alias IM.Cluster.FanoutBatcher
  alias Pb.Im.Protocol.ChatMessage

  test "deliver_messages 按 priority 排序后再推送" do
    parent = self()

    {:ok, pid} =
      Task.start_link(fn ->
        receive do
          {:im_push, bin, meta} -> send(parent, {:got, bin, meta})
        end
      end)

    low = %ChatMessage{msg_id: "low", priority: :MSG_PRIORITY_LOW, inbox_seq: 1, conv_id: "c"}
    high = %ChatMessage{msg_id: "high", priority: :MSG_PRIORITY_HIGH, inbox_seq: 2, conv_id: "c"}

    assert :ok = FanoutBatcher.deliver_messages(pid, [low, high], trace_id: "t")
    assert_receive {:got, bin, meta}, 500
    assert is_binary(bin)
    assert meta.priority == :MSG_PRIORITY_HIGH
  end

  test "deliver_encoded 携带 priority meta" do
    parent = self()

    {:ok, pid} =
      Task.start_link(fn ->
        receive do
          {:im_push, bin, meta} -> send(parent, {:got, bin, meta})
        end
      end)

    assert :ok = FanoutBatcher.deliver_encoded([pid], <<"x">>, priority: :high, inbox_seq: 9)
    assert_receive {:got, <<"x">>, %{priority: :high, inbox_seq: 9}}, 500
  end
end

