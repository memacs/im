defmodule IM.Hooks.RunHooksFlagTest do
  use ExUnit.Case, async: true

  alias IM.Domain.MessageContext
  alias IM.Hooks.PreSend
  alias Pb.Im.Protocol.ChatMessage

  test "run_hooks=false 跳过链" do
    msg = %ChatMessage{content: "x"}

    ctx = %MessageContext{
      app_key: "a",
      user_id: "u",
      device_id: "d",
      trace_id: "t",
      run_hooks: false
    }

    assert {:ok, ^msg} = PreSend.run(msg, ctx)
  end
end
