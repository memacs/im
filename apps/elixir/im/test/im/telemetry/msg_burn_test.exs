defmodule IM.Telemetry.MsgBurnTest do
  use ExUnit.Case, async: false

  alias IM.Telemetry.MsgBurn

  setup do
    handler_id = "msg-burn-test-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach_many(
      handler_id,
      [
        [:im, :msg_burn, :scheduled],
        [:im, :msg_burn, :executed]
      ],
      fn event, measurements, _meta, _ ->
        send(parent, {:telemetry, event, measurements})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "scheduled / executed 发出 telemetry" do
    assert :ok = MsgBurn.scheduled()
    assert_receive {:telemetry, [:im, :msg_burn, :scheduled], %{count: 1}}

    assert :ok = MsgBurn.executed(25)
    assert_receive {:telemetry, [:im, :msg_burn, :executed], %{count: 1, lag: lag}}
    assert is_integer(lag) and lag >= 0
  end
end
