defmodule IM.Client.CommandsTest do
  use ExUnit.Case, async: true

  alias IM.Client.{Assertions, Connection, FakeTransport, Scenario}
  alias IM.Client.Protocol.Codec
  alias Pb.Im.Protocol.{AuthResp, CmdType, Packet}

  setup do
    {:ok, client} = Connection.start_link(url: "ws://fake/ws", transport: FakeTransport)
    :ok = Connection.connect(client)
    tpid = :sys.get_state(client).transport_pid
    :ok = auth!(client, tpid)
    %{client: client, tpid: tpid}
  end

  test "request offline_pull 等待同 seq", %{client: client, tpid: tpid} do
    task = Task.async(fn -> Connection.offline_pull(client, %{limit: 10}) end)
    Process.sleep(15)

    {:ok, bin} =
      Codec.encode(%Packet{
        ver: 1,
        cmd: CmdType.value(:CMD_OFFLINE_PULL_RESP),
        seq: 2,
        payload: <<>>
      })

    FakeTransport.inject(tpid, bin)
    assert {:ok, %Packet{seq: 2}} = Task.await(task)
  end

  test "ack_client_received / create_group / add_friend 发出帧", %{client: client, tpid: tpid} do
    assert :ok = Connection.ack_client_received(client, %{msg_id: "m1"})
    assert FakeTransport.last_sent(tpid) != nil

    task2 = Task.async(fn -> Connection.create_group(client, %{name: "g"}) end)
    Process.sleep(10)
    inject_seq(tpid, 3, :CMD_GROUP_CREATE_RESP)
    assert {:ok, _} = Task.await(task2)

    task3 = Task.async(fn -> Connection.add_friend(client, %{to_user_id: "u2"}) end)
    Process.sleep(10)
    inject_seq(tpid, 4, :CMD_FRIEND_ADD_RESP)
    assert {:ok, _} = Task.await(task3)
  end

  test "管理命令：block / kick / ack_batch / msg_read", %{client: client, tpid: tpid} do
    task = Task.async(fn -> Connection.block_friend(client, "u2") end)
    Process.sleep(10)
    inject_seq(tpid, 2, :CMD_FRIEND_BLOCK_RESP)
    assert {:ok, _} = Task.await(task)

    task2 =
      Task.async(fn ->
        Connection.kick_group_members(client, %{group_id: "g1", member_uids: ["u3"]})
      end)

    Process.sleep(10)
    inject_seq(tpid, 3, :CMD_GROUP_KICK_PUSH)
    assert {:ok, _} = Task.await(task2)

    assert :ok = Connection.ack_batch(client, [%{msg_id: "m1"}])
    assert FakeTransport.last_sent(tpid) != nil

    assert :ok =
             Connection.msg_read(client, %{msg_id: "m1", conv_id: "c1", to: "u2"})
  end

  test "assert_push 按 cmd 等待", %{client: client, tpid: tpid} do
    task = Task.async(fn -> Assertions.assert_push(client, timeout: 2_000) end)
    Process.sleep(10)

    {:ok, bin} =
      Codec.encode(%Packet{
        ver: 1,
        cmd: CmdType.value(:CMD_MSG_PUSH),
        seq: 0,
        payload: <<>>
      })

    FakeTransport.inject(tpid, bin)
    assert {:ok, %Packet{cmd: cmd}} = Task.await(task)
    assert cmd == CmdType.value(:CMD_MSG_PUSH)
  end

  test "Scenario.start_pair + connect" do
    assert {:ok, pair} =
             Scenario.start_pair(url: "ws://fake/a", transport: FakeTransport)

    assert :ok = Scenario.connect_pair(pair)
    assert Connection.status(pair.a) == :connected
    assert Connection.status(pair.b) == :connected
  end

  defp auth!(client, tpid) do
    task =
      Task.async(fn ->
        Connection.authenticate(client, %{
          app_key: "a",
          user_id: "u",
          token: "t",
          device_id: "d"
        })
      end)

    Process.sleep(10)

    {:ok, auth_bin} =
      Codec.encode(%Packet{
        ver: 1,
        cmd: CmdType.value(:CMD_AUTH_RESP),
        seq: 1,
        payload: AuthResp.encode(%AuthResp{user_id: "u"})
      })

    FakeTransport.inject(tpid, auth_bin)
    assert {:ok, _} = Task.await(task)
    :ok
  end

  defp inject_seq(tpid, seq, cmd_atom) do
    {:ok, bin} =
      Codec.encode(%Packet{
        ver: 1,
        cmd: CmdType.value(cmd_atom),
        seq: seq,
        payload: <<>>
      })

    FakeTransport.inject(tpid, bin)
  end
end
