defmodule IM.WebSocket.ConnectionStateTest do
  use ExUnit.Case, async: true

  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.CmdType

  test "未鉴权仅允许 AUTH" do
    assert :ok = ConnectionState.allow?(:unauthenticated, CmdType.value(:CMD_AUTH_REQ))
    assert {:error, :silent_close} = ConnectionState.allow?(:unauthenticated, CmdType.value(:CMD_HEARTBEAT_REQ))
  end

  test "已鉴权禁止再 AUTH，允许心跳与消息/离线 cmd" do
    assert {:error, :already_authenticated} =
             ConnectionState.allow?(:authenticated, CmdType.value(:CMD_AUTH_REQ))

    assert :ok = ConnectionState.allow?(:authenticated, CmdType.value(:CMD_HEARTBEAT_REQ))
    assert :ok = ConnectionState.allow?(:authenticated, CmdType.value(:CMD_MSG_SEND))
    assert :ok = ConnectionState.allow?(:authenticated, CmdType.value(:CMD_OFFLINE_PULL_REQ))
  end

  test "已鉴权未知 cmd 为 invalid_cmd" do
    assert {:error, :invalid_cmd} = ConnectionState.allow?(:authenticated, 65_535)
  end
end
