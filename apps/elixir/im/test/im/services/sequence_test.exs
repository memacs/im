defmodule IM.Services.SequenceTest do
  use IM.DataCase, async: false

  alias IM.Cache.Memory
  alias IM.Services.Sequence

  setup do
    Memory.reset!()
    previous = Application.get_env(:im, :cache)
    Application.put_env(:im, :cache, Memory)

    on_exit(fn ->
      Memory.reset!()

      if previous do
        Application.put_env(:im, :cache, previous)
      else
        Application.delete_env(:im, :cache)
      end
    end)

    :ok
  end

  test "默认走 PG 发号且单调递增" do
    Application.delete_env(:im, :cache)
    a = Sequence.next("app_seq", "conv_seq", "p:u1:u2")
    b = Sequence.next("app_seq", "conv_seq", "p:u1:u2")
    assert b == a + 1
  end

  test "Cache 发号：冷启动从 PG 播种后 INCR" do
    # 先用 PG 推到 3
    Application.delete_env(:im, :cache)
    _ = Sequence.next("app_seed", "inbox_seq", "u9")
    _ = Sequence.next("app_seed", "inbox_seq", "u9")
    n = Sequence.next("app_seed", "inbox_seq", "u9")
    assert n == 3

    Application.put_env(:im, :cache, Memory)
    Memory.reset!()

    # 冷启动应读到 PG=3，再 INCR → 4
    assert Sequence.next("app_seed", "inbox_seq", "u9") == 4
    assert Sequence.next("app_seed", "inbox_seq", "u9") == 5
  end

  test "Cache 不可用时回退 PG" do
    Application.put_env(:im, :cache, IM.Services.SequenceTest.FailingCache)
    a = Sequence.next("app_fb", "conv_seq", "p:a:b")
    b = Sequence.next("app_fb", "conv_seq", "p:a:b")
    assert b == a + 1
  end

  defmodule FailingCache do
    @moduledoc false
    @behaviour IM.Cache

    @impl true
    def incr(_key), do: {:error, :down}

    @impl true
    def get(_key), do: {:error, :down}

    @impl true
    def set(_key, _value), do: {:error, :down}

    @impl true
    def set_nx(_key, _value, _ttl), do: {:error, :down}

    @impl true
    def set_ex(_key, _value, _ttl), do: {:error, :down}

    @impl true
    def del(_key), do: {:error, :down}

    @impl true
    def exists?(_key), do: {:error, :down}

    @impl true
    def sadd(_key, _member), do: {:error, :down}

    @impl true
    def srem(_key, _member), do: {:error, :down}

    @impl true
    def sismember(_key, _member), do: {:error, :down}

    @impl true
    def zadd(_key, _member, _score), do: {:error, :down}

    @impl true
    def zrem(_key, _member), do: {:error, :down}

    @impl true
    def zscore(_key, _member), do: {:error, :down}
  end
end


