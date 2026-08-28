defmodule IM.Client.ConnectionTest do
  use ExUnit.Case, async: true

  alias IM.Client.{Connection, FakeTransport}
  alias IM.Client.Protocol.Codec
  alias Pb.Im.Protocol.{AuthResp, CmdType, HeartbeatResp, Packet}

  setup do
    {:ok, client} =
      Connection.start_link(url: "ws://fake/ws", transport: FakeTransport)

    :ok = Connection.connect(client)
    tpid = :sys.get_state(client).transport_pid
    %{client: client, tpid: tpid}
  end

  test "authenticate 等到 AUTH_RESP 后状态为 authenticated", %{client: client, tpid: tpid} do
    task =
      Task.async(fn ->
        Connection.authenticate(client, %{
          app_key: "app",
          user_id: "u1",
          token: "tok",
          device_id: "d1"
        })
      end)

    Process.sleep(20)
    assert is_binary(FakeTransport.last_sent(tpid))

    {:ok, resp_bin} =
      Codec.encode(%Packet{
        ver: 1,
        cmd: CmdType.value(:CMD_AUTH_RESP),
        seq: 1,
        payload: AuthResp.encode(%AuthResp{user_id: "u1", server_time: 1})
      })

    FakeTransport.inject(tpid, resp_bin)
    assert {:ok, %{user_id: "u1"}} = Task.await(task)
    assert Connection.status(client) == :authenticated
  end

  test "heartbeat 匹配 seq", %{client: client, tpid: tpid} do
    # 先鉴权
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

    hb_task = Task.async(fn -> Connection.heartbeat(client) end)
    Process.sleep(10)

    {:ok, hb_bin} =
      Codec.encode(%Packet{
        ver: 1,
        cmd: CmdType.value(:CMD_HEARTBEAT_RESP),
        seq: 2,
        payload: HeartbeatResp.encode(%HeartbeatResp{server_time: 9})
      })

    FakeTransport.inject(tpid, hb_bin)
    assert {:ok, %Packet{cmd: cmd, seq: 2}} = Task.await(hb_task)
    assert cmd == CmdType.value(:CMD_HEARTBEAT_RESP)
  end
end
