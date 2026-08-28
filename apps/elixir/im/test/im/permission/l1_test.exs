defmodule IM.Permission.L1Test do
  use ExUnit.Case, async: false

  alias IM.Permission.{Invalidator, L1}

  setup do
    L1.reset!()
    :ok
  end

  test "put/get 与过期 miss" do
    key = L1.block_key("a", "u1", "u2")
    assert :miss = L1.get(key)
    :ok = L1.put(key, true)
    assert {:ok, true} = L1.get(key)
  end

  test "invalidate block 清除该 blocker 下条目" do
    :ok = L1.put(L1.block_key("a", "u1", "x"), true)
    :ok = L1.put(L1.block_key("a", "u1", "y"), false)
    :ok = L1.put(L1.block_key("a", "u2", "x"), true)

    :ok = L1.invalidate({:block, "a", "u1"})
    assert :miss = L1.get(L1.block_key("a", "u1", "x"))
    assert :miss = L1.get(L1.block_key("a", "u1", "y"))
    assert {:ok, true} = L1.get(L1.block_key("a", "u2", "x"))
  end

  test "Invalidator.broadcast 清本节点 L1" do
    key = L1.mute_key("a", "g1", "u1")
    :ok = L1.put(key, true)
    :ok = Invalidator.broadcast({:mute, "a", "g1"})
    # 本地 subscriber 同步处理
    assert :miss = L1.get(key)
  end
end
