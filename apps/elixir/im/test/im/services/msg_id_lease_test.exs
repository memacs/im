defmodule IM.Services.MsgIdLeaseTest do
  use IM.DataCase, async: false

  alias IM.Cache.Memory
  alias IM.Services.MsgId
  alias IM.Services.MsgId.Lease
  alias IM.Stores.IdWorkerStore

  setup do
    Memory.reset!()
    :ok
  end

  test "acquire 占用 Cache 与 PG 镜像" do
    assert {:ok, id} = Lease.acquire("test@node")
    assert id in 0..1023
    assert {:ok, "test@node"} = IM.Cache.get("im:id:worker:#{id}")
    assert :ok = Lease.release(id, "test@node")
  end

  test "MsgId.next 产出 Snowflake（T=0）且持有 worker" do
    wid = MsgId.worker_id()
    assert is_integer(wid)

    msg_id = MsgId.next("app_lease_#{System.unique_integer([:positive])}")
    id = String.to_integer(msg_id)
    assert Bitwise.bsr(id, 62) == 0
    worker = Bitwise.band(Bitwise.bsr(id, 12), 0x3FF)
    assert worker == wid
  end

  test "IdWorkerStore upsert" do
    until = DateTime.utc_now() |> DateTime.add(30, :second) |> DateTime.truncate(:microsecond)
    assert :ok = IdWorkerStore.upsert(42, "n@h", until)
    assert :ok = IdWorkerStore.delete(42)
  end
end
