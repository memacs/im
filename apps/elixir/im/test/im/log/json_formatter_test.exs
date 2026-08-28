defmodule IM.Log.JsonFormatterTest do
  use ExUnit.Case, async: true

  alias IM.Log.JsonFormatter

  test "输出单行 NDJSON 且 message 等于 event" do
    event = %{
      level: :warning,
      msg: {:string, "packet_error"},
      meta: %{
        event: :packet_error,
        time: System.system_time(:microsecond),
        code: 2004,
        caller_module: IM.Services.MessageSend,
        reason: "conv_not_found"
      }
    }

    iodata = JsonFormatter.format(event, %{})
    line = iodata |> IO.iodata_to_binary() |> String.trim_trailing("\n")
    assert String.split(line, "\n") == [line]

    {:ok, map} = Jason.decode(line)
    assert map["event"] == "packet_error"
    assert map["message"] == "packet_error"
    assert map["service"] == "im"
    assert map["level"] == "warning"
    assert map["code"] == 2004
    assert is_binary(map["@timestamp"])
    assert is_binary(map["host"])
    assert is_binary(map["node"])
    assert map["caller_module"] =~ "MessageSend"
  end
end
