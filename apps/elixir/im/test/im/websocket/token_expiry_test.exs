defmodule IM.WebSocket.TokenExpiryTest do
  use ExUnit.Case, async: true

  alias IM.WebSocket.TokenExpiry

  test "delay_ms 已过期返回 0" do
    past = DateTime.utc_now() |> DateTime.add(-60, :second)
    assert TokenExpiry.delay_ms(past) == 0
  end

  test "delay_ms 未来时间为正" do
    future = DateTime.utc_now() |> DateTime.add(30, :second)
    assert TokenExpiry.delay_ms(future) >= 29_000
  end
end
