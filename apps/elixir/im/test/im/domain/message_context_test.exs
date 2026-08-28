defmodule IM.Domain.MessageContextTest do
  use ExUnit.Case, async: true

  alias IM.Domain.MessageContext

  test "from_http_client 默认控制项" do
    ctx =
      MessageContext.from_http_client(%{
        app_key: "a",
        user_id: "u",
        device_id: "d",
        trace_id: "t"
      })

    assert ctx.source == :http_client
    assert ctx.write_kafka == true
    assert ctx.run_hooks == true
  end

  test "from_http_internal 带 caller" do
    ctx =
      MessageContext.from_http_internal(%{
        app_key: "a",
        user_id: "u",
        device_id: "internal",
        trace_id: "t",
        caller_service: "ops",
        write_kafka: false
      })

    assert ctx.source == :http_internal
    assert ctx.caller_service == "ops"
    assert ctx.write_kafka == false
  end
end
