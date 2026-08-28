defmodule IM.Services.ChannelTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Channel.RateLimiter
  alias IM.Domain.MessageContext
  alias IM.EventBus.Buffer
  alias IM.Protocol.Codec
  alias IM.Services.Channel
  alias Pb.Im.Protocol.{ChannelPublish, ChannelPush, CmdType, Packet}

  setup do
    RateLimiter.reset()
    user = AuthFixtures.create_user!(user_id: "ch_#{System.unique_integer([:positive])}")
    ctx = ctx(user)

    prev_enabled = Application.get_env(:im, :event_bus_enabled)
    prev_impl = Application.get_env(:im, :event_bus)

    on_exit(fn ->
      restore(:event_bus_enabled, prev_enabled)
      restore(:event_bus, prev_impl)
    end)

    %{user: user, ctx: ctx}
  end

  test "subscribe + publish_down 本进程收到 CHANNEL_PUSH", %{ctx: ctx} do
    assert {:ok, resp} = Channel.subscribe(["fleet:alert"], ctx, pubsub: true)
    assert resp.subscribed == ["fleet:alert"]

    assert {:ok, %{event_id: eid}} =
             Channel.publish_down(ctx.app_key, "fleet:alert", %{payload: "hi"}, "ops")

    assert_receive {:channel_push, bin}, 500
    assert {:ok, %Packet{cmd: cmd, seq: 0, payload: payload}} = Codec.decode(bin)
    assert cmd == CmdType.value(:CMD_CHANNEL_PUSH)

    assert %ChannelPush{channel_id: "fleet:alert", event_id: ^eid, payload: "hi"} =
             ChannelPush.decode(payload)
  end

  test "上行 ACK 且旁路 app_events", %{ctx: ctx} do
    Application.put_env(:im, :event_bus_enabled, true)
    Application.put_env(:im, :event_bus, IM.EventBus.Buffered)
    before = length(Buffer.snapshot())

    req = %ChannelPublish{
      channel_id: "order:status",
      content_type: "application/json",
      payload: "{\"ok\":1}",
      client_event_id: "c1"
    }

    assert {:ok, ack} = Channel.publish_up(req, ctx)
    assert ack.accepted
    assert ack.event_id != ""

    assert wait_until(fn -> length(Buffer.snapshot()) > before end)

    assert Enum.any?(Buffer.snapshot(), fn {t, e} ->
             t == :app_events and e.direction == :APP_EVENT_UP and e.event_id == ack.event_id
           end)
  end

  test "超限静默丢", %{ctx: ctx} do
    Application.put_env(:im, :channel_publish_burst, 2)
    Application.put_env(:im, :channel_publish_rate_per_conn, 1)

    req = %ChannelPublish{channel_id: "fleet:alert", payload: "x"}

    assert {:ok, _} = Channel.publish_up(req, ctx)
    assert {:ok, _} = Channel.publish_up(req, ctx)
    assert :drop_silent = Channel.publish_up(req, ctx)
  end

  test "非法 channel_id 订阅失败", %{ctx: ctx} do
    assert {:ok, resp} = Channel.subscribe(["bad"], ctx, pubsub: false)
    assert resp.subscribed == []
    assert [%{channel_id: "bad"}] = resp.failed
  end

  test "unsubscribe 取消 PubSub", %{ctx: ctx} do
    assert {:ok, _} = Channel.subscribe(["fleet:alert"], ctx, pubsub: true)
    assert {:ok, u} = Channel.unsubscribe(["fleet:alert"], ctx, pubsub: true)
    assert u.unsubscribed == ["fleet:alert"]

    assert {:ok, _} =
             Channel.publish_down(ctx.app_key, "fleet:alert", %{payload: "x"}, "ops")

    refute_receive {:channel_push, _}, 100
  end

  defp ctx(user) do
    %MessageContext{
      app_key: user.app_key,
      user_id: user.user_id,
      device_id: "d-ch",
      session_id: "s",
      trace_id: "t-ch",
      node: node()
    }
  end

  defp wait_until(fun, n \\ 40) do
    cond do
      fun.() ->
        true

      n <= 0 ->
        false

      true ->
        # 轮询直至 channel 订阅状态可见
        Process.sleep(10)
        wait_until(fun, n - 1)
    end
  end

  defp restore(key, nil), do: Application.delete_env(:im, key)
  defp restore(key, val), do: Application.put_env(:im, key, val)
end
