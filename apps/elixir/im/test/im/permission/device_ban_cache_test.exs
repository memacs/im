defmodule IM.Permission.DeviceBanCacheTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Cache.Memory
  alias IM.Permission.{DeviceBanCache, L1}
  alias IM.Services.DeviceBan

  setup do
    Memory.reset!()
    L1.reset!()
    user = AuthFixtures.create_user!(user_id: "dban_#{System.unique_integer([:positive])}")
    %{user: user}
  end

  test "ban 写穿后 ensure_allowed 拒绝", %{user: user} do
    assert :ok = DeviceBanCache.ensure_allowed(user.app_key, user.user_id, "d1")
    assert :ok = DeviceBan.ban(user.app_key, user.user_id, "d1", "risk")
    assert DeviceBanCache.banned?(user.app_key, user.user_id, "d1")

    assert {:error, %{msg: "device_banned"}} =
             DeviceBanCache.ensure_allowed(user.app_key, user.user_id, "d1")
  end
end
