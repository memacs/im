defmodule IM.EventBus.SessionPushTest do
  use ExUnit.Case, async: false

  alias IM.Domain.MessageContext
  alias IM.EventBus.{Buffer, Push, Session}

  setup do
    prev_e = Application.get_env(:im, :event_bus_enabled)
    prev_i = Application.get_env(:im, :event_bus)
    prev_k = Application.get_env(:im, :event_bus_kafka)
    Application.put_env(:im, :event_bus_enabled, true)
    Application.put_env(:im, :event_bus, IM.EventBus.Buffered)

    on_exit(fn ->
      restore(:event_bus_enabled, prev_e)
      restore(:event_bus, prev_i)
      restore(:event_bus_kafka, prev_k)
    end)

    :ok
  end

  test "heartbeat :off 不入队；:all 入队" do
    ctx = %MessageContext{
      app_key: "a",
      user_id: "u",
      device_id: "d",
      session_id: "s",
      trace_id: "t",
      node: node()
    }

    Application.put_env(
      :im,
      :event_bus_kafka,
      Keyword.put(Application.get_env(:im, :event_bus_kafka, []), :session_heartbeat_mode, :off)
    )

    before = length(Buffer.snapshot())
    assert :ok = Session.heartbeat(ctx)
    Process.sleep(20)
    assert length(Buffer.snapshot()) == before

    Application.put_env(
      :im,
      :event_bus_kafka,
      Keyword.put(Application.get_env(:im, :event_bus_kafka, []), :session_heartbeat_mode, :all)
    )

    assert :ok = Session.heartbeat(ctx)

    assert wait(fn ->
             Enum.any?(Buffer.snapshot(), fn {t, e} -> t == :session and e.type == "heartbeat" end)
           end)
  end

  test "push batch 超 500 分块" do
    before = length(Buffer.snapshot())

    targets =
      for i <- 1..501, do: %{user_id: "u", device_id: "d#{i}", platform: "ios", push_token: "t"}

    assert :ok = Push.publish_batch("mid-1", targets, app_key: "a")

    assert wait(fn ->
             Buffer.snapshot()
             |> Enum.count(fn {t, e} -> t == :push and e.msg_id == "mid-1" end) == 2
           end)

    assert length(Buffer.snapshot()) >= before + 2
  end

  defp wait(fun, n \\ 40) do
    cond do
      fun.() ->
        true

      n <= 0 ->
        false

      true ->
        Process.sleep(10)
        wait(fun, n - 1)
    end
  end

  defp restore(k, nil), do: Application.delete_env(:im, k)
  defp restore(k, v), do: Application.put_env(:im, k, v)
end
