defmodule IM.Release.SmokeTest do
  use IM.DataCase, async: false

  alias IM.Cache.Memory

  test "messaging/0 单聊未读与已读" do
    Memory.reset!()
    assert :ok = IM.Release.Smoke.messaging()
  end

  test "auth/0 REST 登录" do
    Memory.reset!()
    assert :ok = IM.Release.Smoke.auth()
  end
end
