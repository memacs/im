defmodule IMWeb.PacketTransportTest do
  @moduledoc """
  PacketTransport 周期 drain 行为测试（设计 §7.6）。

  验证 G-40 修复后：
  1. push_via_queue 只入队不立即 drain（队列堆积）
  2. :drain_tick 周期触发 drain_outbound
  3. 多带同时积压时 WFQ 优先级生效
  """
  use ExUnit.Case, async: true

  alias IM.Delivery.OutboundQueue
  alias IMWeb.PacketTransport
  alias IM.WebSocket.ConnectionState

  setup do
    prev = %{
      high: Application.get_env(:im, :priority_weight_high),
      normal: Application.get_env(:im, :priority_weight_normal),
      low: Application.get_env(:im, :priority_weight_low),
      burst: Application.get_env(:im, :priority_max_burst),
      drain_interval: Application.get_env(:im, :outbound_drain_interval_ms)
    }

    on_exit(fn ->
      Enum.each(prev, fn
        {:high, v} -> set_env(:priority_weight_high, v)
        {:normal, v} -> set_env(:priority_weight_normal, v)
        {:low, v} -> set_env(:priority_weight_low, v)
        {:burst, v} -> set_env(:priority_max_burst, v)
        {:drain_interval, v} -> set_env(:outbound_drain_interval_ms, v)
      end)
    end)

    :ok
  end

  describe "push_via_queue 只入队不 drain（设计 §7.6）" do
    test "NORMAL 入队后队列非空，等 :drain_tick" do
      state = fresh_state()

      assert {:ok, state2} =
               PacketTransport.handle_info({:im_push, "bin1", %{priority: :normal}}, state)

      # 队列里应该有 1 条（不立即 drain）
      assert OutboundQueue.depth(state2.outbound) == 1
    end

    test "HIGH + 队列空 → 直写，不入队" do
      state = fresh_state()

      assert {:push, {:binary, "bin1"}, _state} =
               PacketTransport.handle_info({:im_push, "bin1", %{priority: :high}}, state)
    end

    test "LOW 入队后队列堆积，不立即 drain" do
      state = fresh_state()

      assert {:ok, state2} =
               PacketTransport.handle_info({:channel_push, "bin1"}, state)

      assert OutboundQueue.depth(state2.outbound) == 1
    end

    test "连续 push 20 条 NORMAL → 队列堆积 20 条" do
      state = fresh_state()

      state =
        Enum.reduce(1..20, state, fn i, acc ->
          assert {:ok, acc2} =
                   PacketTransport.handle_info({:im_push, "n#{i}", %{priority: :normal}}, acc)

          acc2
        end)

      assert OutboundQueue.depth(state.outbound) == 20
    end
  end

  describe "drain_outbound 触发 drain" do
    test "队列空 → 返回 {:ok, state} 不发任何 push" do
      state = fresh_state()

      assert {:ok, _} = PacketTransport.drain_outbound(state)
    end

    test "队列有 1 条 NORMAL → drain_outbound 取走并 push" do
      state = fresh_state()

      {:ok, state} =
        PacketTransport.handle_info({:im_push, "bin1", %{priority: :normal}}, state)

      assert {:push, {:binary, "bin1"}, state2} = PacketTransport.drain_outbound(state)
      assert OutboundQueue.empty?(state2.outbound)
    end

    test ":drain_tick 等价于 drain_outbound" do
      state = fresh_state()

      {:ok, state} =
        PacketTransport.handle_info({:im_push, "bin1", %{priority: :normal}}, state)

      assert {:push, {:binary, "bin1"}, state2} =
               PacketTransport.handle_info(:drain_tick, state)

      assert OutboundQueue.empty?(state2.outbound)
    end

    test "队列 > max_burst → 一次 drain 只取 max_burst 条，剩余等下次 tick" do
      Application.put_env(:im, :priority_max_burst, 4)
      state = fresh_state()

      state =
        Enum.reduce(1..10, state, fn i, acc ->
          assert {:ok, acc2} =
                   PacketTransport.handle_info({:im_push, "n#{i}", %{priority: :normal}}, acc)

          acc2
        end)

      # depth = 10, max_burst = 4 → drain 取 4 条
      {:push, bins, state2} = PacketTransport.drain_outbound(state)
      assert length(bins) == 4
      # 队列还剩 6 条
      assert OutboundQueue.depth(state2.outbound) == 6

      # 第二次 drain 取 4
      {:push, bins2, state3} = PacketTransport.drain_outbound(state2)
      assert length(bins2) == 4
      assert OutboundQueue.depth(state3.outbound) == 2

      # 第三次 drain 取 2（队列只剩 2 条）
      {:push, bins3, state4} = PacketTransport.drain_outbound(state3)
      assert length(bins3) == 2
      assert OutboundQueue.empty?(state4.outbound)
    end
  end

  describe "WFQ 优先级在周期 drain 下生效（多带同时积压）" do
    test "HIGH + NORMAL + LOW 同时积压 → WFQ 按 8/4/1 权重选带" do
      Application.put_env(:im, :priority_weight_high, 8)
      Application.put_env(:im, :priority_weight_normal, 4)
      Application.put_env(:im, :priority_weight_low, 1)
      Application.put_env(:im, :priority_max_burst, 16)

      now = System.system_time(:millisecond)

      # 直接构造队列：20 HIGH + 10 NORMAL + 5 LOW
      # 绕开 handle_info 的 HIGH 直写路径，专注测 drain_outbound 的 WFQ 调度
      q = OutboundQueue.new()

      q =
        Enum.reduce(1..20, q, fn i, acc ->
          OutboundQueue.enqueue(acc, %{
            packet_binary: "h#{i}",
            priority: :high,
            inbox_seq: i,
            enqueued_at_ms: now
          })
        end)

      q =
        Enum.reduce(1..10, q, fn i, acc ->
          OutboundQueue.enqueue(acc, %{
            packet_binary: "n#{i}",
            priority: :normal,
            inbox_seq: 20 + i,
            enqueued_at_ms: now
          })
        end)

      q =
        Enum.reduce(1..5, q, fn i, acc ->
          OutboundQueue.enqueue(acc, %{
            packet_binary: "l#{i}",
            priority: :low,
            inbox_seq: 30 + i,
            enqueued_at_ms: now
          })
        end)

      state = %{fresh_state() | outbound: q}

      # 总深度 35
      assert OutboundQueue.depth(state.outbound) == 35

      # drain 一次取 16 条
      {:push, frames, _state2} = PacketTransport.drain_outbound(state)
      assert length(frames) == 16

      # frames 是 [{:binary, "h1"}, {:binary, "n1"}, ...] 形式
      binaries = Enum.map(frames, fn {:binary, b} -> b end)

      # HIGH 占主导（权重 8，约 8/13 ≈ 62%）
      high_count = Enum.count(binaries, &String.starts_with?(&1, "h"))
      normal_count = Enum.count(binaries, &String.starts_with?(&1, "n"))
      low_count = Enum.count(binaries, &String.starts_with?(&1, "l"))

      # HIGH 占比最高，NORMAL 次之，LOW 最少
      assert high_count > normal_count
      assert normal_count >= low_count

      # LOW 至少有 1 条（WFQ 防饿死）
      assert low_count >= 1
    end

    test "LOW 单带积压时仍按 max_burst 出队（不饿死）" do
      Application.put_env(:im, :priority_max_burst, 8)

      now = System.system_time(:millisecond)

      # 直接构造 20 条 LOW
      q =
        Enum.reduce(1..20, OutboundQueue.new(), fn i, acc ->
          OutboundQueue.enqueue(acc, %{
            packet_binary: "l#{i}",
            priority: :low,
            inbox_seq: i,
            enqueued_at_ms: now
          })
        end)

      state = %{fresh_state() | outbound: q}

      assert OutboundQueue.depth(state.outbound) == 20

      {:push, frames, state2} = PacketTransport.drain_outbound(state)
      # 单带也能出队 max_burst 条
      assert length(frames) == 8
      assert OutboundQueue.depth(state2.outbound) == 12
    end
  end

  # 工具函数

  defp fresh_state do
    %{
      conn: ConnectionState.new(),
      auth_timer: nil,
      idle_timer: nil,
      token_timer: nil,
      outbound: OutboundQueue.new(),
      drain_timer: nil
    }
  end

  defp set_env(key, nil), do: Application.delete_env(:im, key)
  defp set_env(key, value), do: Application.put_env(:im, key, value)
end
