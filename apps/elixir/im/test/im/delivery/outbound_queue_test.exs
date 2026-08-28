defmodule IM.Delivery.OutboundQueueTest do
  use ExUnit.Case, async: true

  alias IM.Delivery.OutboundQueue

  setup do
    prev = %{
      high: Application.get_env(:im, :priority_weight_high),
      normal: Application.get_env(:im, :priority_weight_normal),
      low: Application.get_env(:im, :priority_weight_low),
      burst: Application.get_env(:im, :priority_max_burst),
      aging_n: Application.get_env(:im, :priority_aging_normal_ms),
      aging_l: Application.get_env(:im, :priority_aging_low_ms),
      aging_lh: Application.get_env(:im, :priority_aging_low_to_high_ms),
      max_depth: Application.get_env(:im, :outbound_max_depth)
    }

    on_exit(fn ->
      Enum.each(prev, fn {k, v} ->
        key =
          case k do
            :high -> :priority_weight_high
            :normal -> :priority_weight_normal
            :low -> :priority_weight_low
            :burst -> :priority_max_burst
            :aging_n -> :priority_aging_normal_ms
            :aging_l -> :priority_aging_low_ms
            :aging_lh -> :priority_aging_low_to_high_ms
            :max_depth -> :outbound_max_depth
          end

        if is_nil(v), do: Application.delete_env(:im, key), else: Application.put_env(:im, key, v)
      end)
    end)

    :ok
  end

  test "同带按 inbox_seq 升序写出" do
    now = System.system_time(:millisecond)

    q =
      OutboundQueue.new()
      |> enqueue(:normal, "c", 3, now)
      |> enqueue(:normal, "a", 1, now)
      |> enqueue(:normal, "b", 2, now)

    {bins, q2} = OutboundQueue.drain(q, 10)
    assert bins == ["a", "b", "c"]
    assert OutboundQueue.empty?(q2)
  end

  test "HIGH 洪峰下 LOW 仍能获得份额" do
    now = System.system_time(:millisecond)

    q =
      Enum.reduce(1..20, OutboundQueue.new(), fn i, acc ->
        enqueue(acc, :high, "h#{i}", i, now)
      end)
      |> enqueue(:low, "low", 100, now)

    {bins, _} = OutboundQueue.drain(q, 21)
    assert "low" in bins
  end

  test "老化：LOW 等待超过阈值升 NORMAL/HIGH" do
    Application.put_env(:im, :priority_aging_low_ms, 10)
    Application.put_env(:im, :priority_aging_low_to_high_ms, 20)
    Application.put_env(:im, :priority_aging_normal_ms, 10_000)

    old = System.system_time(:millisecond) - 50

    q =
      OutboundQueue.new()
      |> enqueue(:low, "aged", 1, old)
      |> enqueue(:high, "h", 2, System.system_time(:millisecond))

    # aged 已升 HIGH，同带按 inbox_seq：aged(1) 先于 h(2)
    {bins, _} = OutboundQueue.drain(q, 2)
    assert bins == ["aged", "h"]
  end

  test "超 max_depth 丢弃 LOW" do
    Application.put_env(:im, :outbound_max_depth, 2)
    now = System.system_time(:millisecond)

    q =
      OutboundQueue.new()
      |> enqueue(:low, "l1", 1, now)
      |> enqueue(:low, "l2", 2, now)
      |> enqueue(:low, "l3", 3, now)

    assert OutboundQueue.depth(q) == 2
    assert q.dropped == 1
    {bins, _} = OutboundQueue.drain(q, 10)
    assert bins == ["l2", "l3"]
  end

  test "深度超过 coalesce_depth 时合并同带 PUSH" do
    alias IM.Protocol.{Codec, Push}
    alias Pb.Im.Protocol.{ChatMessage, CmdType}

    Application.put_env(:im, :outbound_coalesce_depth, 3)
    Application.put_env(:im, :priority_aging_normal_ms, 86_400_000)
    now = System.system_time(:millisecond)

    bins =
      for i <- 1..4 do
        msg = %ChatMessage{msg_id: "m#{i}", content: "#{i}", conv_id: "c1", inbox_seq: i}
        {:ok, packet} = Push.build(:CMD_MSG_PUSH, msg)
        {:ok, bin} = Codec.encode(packet)
        bin
      end

    q =
      Enum.reduce(Enum.with_index(bins, 1), OutboundQueue.new(), fn {bin, i}, acc ->
        enqueue(acc, :normal, bin, i, now)
      end)

    assert OutboundQueue.depth(q) == 4
    {out, q2} = OutboundQueue.drain(q, 10)
    assert length(out) == 1
    assert OutboundQueue.empty?(q2)

    {:ok, packet} = Codec.decode(hd(out))
    assert packet.cmd == CmdType.value(:CMD_MSG_PUSH_BATCH)
  end

  defp enqueue(q, priority, bin, seq, at) do
    OutboundQueue.enqueue(q, %{
      packet_binary: bin,
      priority: priority,
      inbox_seq: seq,
      enqueued_at_ms: at
    })
  end
end
