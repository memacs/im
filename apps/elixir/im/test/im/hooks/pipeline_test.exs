defmodule IM.Hooks.PipelineTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.Hooks.Pipeline
  alias IM.Services.Message
  alias Pb.Im.Protocol.ChatMessage

  setup do
    previous = Application.get_env(:im, :hooks)
    previous_legacy = Application.get_env(:im, :pre_send_hook)

    on_exit(fn ->
      restore(:hooks, previous)
      restore(:pre_send_hook, previous_legacy)
    end)

    alice = AuthFixtures.create_user!(user_id: "hk_a_#{System.unique_integer([:positive])}")

    bob =
      AuthFixtures.create_user!(
        app_key: alice.app_key,
        user_id: "hk_b_#{System.unique_integer([:positive])}"
      )

    ctx = ctx(alice, "d")
    %{alice: alice, bob: bob, ctx: ctx}
  end

  test "reject 拦截发送", %{bob: bob, ctx: ctx} do
    Application.put_env(:im, :hooks,
      pre_send: [__MODULE__.RejectHook],
      on_exception: :fail_closed
    )

    assert {:error, %{code: :msg_invalid}} =
             Message.send(text_msg(bob.user_id, "x"), ctx)
  end

  test "可改写 content", %{bob: bob, ctx: ctx} do
    Application.put_env(:im, :hooks,
      pre_send: [__MODULE__.RewriteHook],
      on_exception: :fail_closed
    )

    assert {:ok, result} = Message.send(text_msg(bob.user_id, "raw"), ctx)
    assert result.message.content == "rewritten"
  end

  test "fail_closed：异常拦截", %{bob: bob, ctx: ctx} do
    Application.put_env(:im, :hooks, pre_send: [__MODULE__.BoomHook], on_exception: :fail_closed)

    assert {:error, %{code: :internal_error}} =
             Message.send(text_msg(bob.user_id, "x"), ctx)
  end

  test "fail_open：异常后继续发送", %{bob: bob, ctx: ctx} do
    Application.put_env(:im, :hooks, pre_send: [__MODULE__.BoomHook], on_exception: :fail_open)

    assert {:ok, _} = Message.send(text_msg(bob.user_id, "ok"), ctx)
  end

  test "Pipeline 直接跑空链返回原消息", %{bob: bob, ctx: ctx} do
    Application.put_env(:im, :hooks, pre_send: [], on_exception: :fail_closed)
    msg = text_msg(bob.user_id, "n")
    assert {:ok, ^msg} = Pipeline.run_pre_send(msg, ctx)
  end

  defmodule RejectHook do
    @behaviour IM.Hooks.Behaviour
    @impl true
    def pre_send(_msg, _ctx), do: {:reject, :blocked}
  end

  defmodule RewriteHook do
    @behaviour IM.Hooks.Behaviour
    @impl true
    def pre_send(msg, _ctx), do: {:ok, %{msg | content: "rewritten"}}
  end

  defmodule BoomHook do
    @behaviour IM.Hooks.Behaviour
    @impl true
    def pre_send(_msg, _ctx), do: raise("boom")
  end

  defp text_msg(to, content) do
    %ChatMessage{
      chat_type: :CHAT_PRIVATE,
      to: to,
      msg_type: :MSG_TEXT,
      content: content,
      client_msg_id: "hk-#{System.unique_integer([:positive])}"
    }
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
