defmodule IM.EventBusTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.EventBus
  alias IM.EventBus.Buffer
  alias IM.Services.Message
  alias Pb.Im.Protocol.ChatMessage

  setup do
    prev_enabled = Application.get_env(:im, :event_bus_enabled)
    prev_impl = Application.get_env(:im, :event_bus)

    on_exit(fn ->
      restore(:event_bus_enabled, prev_enabled)
      restore(:event_bus, prev_impl)
    end)

    alice = AuthFixtures.create_user!(user_id: "eb_a_#{System.unique_integer([:positive])}")
    bob = AuthFixtures.create_user!(app_key: alice.app_key, user_id: "eb_b_#{System.unique_integer([:positive])}")
    %{alice: alice, bob: bob, ctx: ctx(alice, "d")}
  end

  test "禁用时 publish 为空操作" do
    Application.put_env(:im, :event_bus_enabled, false)
    assert :ok = EventBus.publish(:upstream, %{msg_id: "x"})
  end

  test "Buffered 入队且不阻塞 SEND", %{bob: bob, ctx: ctx} do
    Application.put_env(:im, :event_bus_enabled, true)
    Application.put_env(:im, :event_bus, IM.EventBus.Buffered)

    before = length(Buffer.snapshot())

    assert {:ok, result} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_PRIVATE,
                 to: bob.user_id,
                 msg_type: :MSG_TEXT,
                 content: "e",
                 client_msg_id: "eb-#{System.unique_integer([:positive])}"
               },
               ctx
             )

    assert result.ack.status == :ACK_SERVER_RECEIVED

    # cast 异步，短暂自旋
    assert wait_until(fn -> length(Buffer.snapshot()) > before end)

    assert Enum.any?(Buffer.snapshot(), fn {t, e} ->
             t == :upstream and e.msg_id == result.message.msg_id and e.payload != <<>>
           end)
  end

  defp wait_until(fun, n \\ 40) do
    cond do
      fun.() -> true
      n <= 0 -> false
      true ->
        Process.sleep(10)
        wait_until(fun, n - 1)
    end
  end

  defp ctx(user, device) do
    %MessageContext{
      app_key: user.app_key,
      user_id: user.user_id,
      device_id: device,
      session_id: "s-#{device}",
      trace_id: "t",
      node: node()
    }
  end

  defp restore(key, nil), do: Application.delete_env(:im, key)
  defp restore(key, val), do: Application.put_env(:im, key, val)
end
