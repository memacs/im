defmodule IM.EventBus.DownstreamTest do
  use ExUnit.Case, async: false

  alias IM.EventBus.Buffer
  alias IM.EventBus.Downstream

  setup do
    prev_e = Application.get_env(:im, :event_bus_enabled)
    prev_i = Application.get_env(:im, :event_bus)
    Application.put_env(:im, :event_bus_enabled, true)
    Application.put_env(:im, :event_bus, IM.EventBus.Buffered)

    on_exit(fn ->
      restore(:event_bus_enabled, prev_e)
      restore(:event_bus, prev_i)
    end)

    :ok
  end

  test "5000 规模群只写 1 条 aggregated downstream" do
    before = length(Buffer.snapshot())
    recipients = for i <- 1..5000, do: "u#{i}"
    payload = <<1, 2, 3>>

    assert :ok =
             Downstream.publish_push(
               %{
                 msg_id: "m-big",
                 chat_type: :CHAT_GROUP,
                 to: "gbig",
                 app_key: "app",
                 member_count: 5000
               },
               recipients,
               %{
                 from_user_id: "owner",
                 app_key: "app",
                 trace_id: "tr",
                 cmd: 101,
                 payload: payload
               }
             )

    assert wait(fn -> length(Buffer.snapshot()) > before end)

    downs =
      Buffer.snapshot()
      |> Enum.filter(fn {t, e} -> t == :downstream and e.msg_id == "m-big" end)

    assert length(downs) == 1
    [{_, event}] = downs
    assert event.fanout.mode in [:group_aggregated, :direct]
    assert event.fanout.recipient_count == 5000
    assert event.payload == payload
    assert event.cmd == 101
    assert event.trace_id == "tr"

    if event.fanout.mode == :group_aggregated do
      assert length(event.fanout.audience.recipient_user_ids) <= 500
      assert event.fanout.audience.recipient_list_truncated == true
    end
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
