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

  test "元数据键、时间格式与兜底分支" do
    event = %{
      level: :info,
      msg: "plain",
      meta: [
        event: :ws_connect,
        trace_id: "t1",
        time: {{2024, 1, 2}, {3, 4, 5, 123_456}}
      ]
    }

    line = event |> JsonFormatter.format(%{}) |> IO.iodata_to_binary() |> String.trim()
    {:ok, map} = Jason.decode(line)
    assert map["event"] == "ws_connect"
    assert map["trace_id"] == "t1"
    assert String.starts_with?(map["@timestamp"], "2024-01-02")

    assert JsonFormatter.format(%{level: :error, msg: {:string, "x"}, meta: %{}}, %{}) != []
    assert JsonFormatter.format(%{oops: true}, %{}) == []
  end
end
