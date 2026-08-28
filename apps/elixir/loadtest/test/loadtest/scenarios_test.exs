defmodule IM.LoadTest.ScenariosTest do
  use ExUnit.Case, async: true

  test "场景模块可加载" do
    assert Code.ensure_loaded?(IM.LoadTest.Scenarios.ConnectionLoad)
    assert Code.ensure_loaded?(IM.LoadTest.Scenarios.MessageFlood)
    assert Code.ensure_loaded?(IM.LoadTest.Scenarios.ChannelSubscribe)
    assert Code.ensure_loaded?(IM.LoadTest.Scenarios.GroupFanout)
    assert Code.ensure_loaded?(IM.LoadTest.Scenarios.RoomBroadcast)
    assert Code.ensure_loaded?(IM.LoadTest.Scenarios.UnreadBump)
    assert Code.ensure_loaded?(IM.LoadTest.UserBootstrap)
  end
end
