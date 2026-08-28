defmodule IM.Channel.RateLimiterTest do
  use ExUnit.Case, async: false

  alias IM.Channel.RateLimiter

  setup do
    RateLimiter.reset()
    :ok
  end

  test "burst 内允许，超出 rate_limited" do
    Application.put_env(:im, :channel_publish_rate_per_conn, 1)
    Application.put_env(:im, :channel_publish_burst, 2)

    assert :ok = RateLimiter.allow_conn?("a", "u", "d")
    assert :ok = RateLimiter.allow_conn?("a", "u", "d")
    assert :rate_limited = RateLimiter.allow_conn?("a", "u", "d")
  end
end
