defmodule IM.Client.Assertions do
  @moduledoc "按 `seq` / `cmd` 等待入站 Packet 的测试辅助（仅 `test/support`）。"

  alias IM.Client.Connection
  alias Pb.Im.Protocol.{CmdType, Packet}

  @doc "等待指定 `cmd` 的 Packet。"
  @spec await_cmd(pid(), non_neg_integer(), timeout()) :: {:ok, Packet.t()} | {:error, term()}
  def await_cmd(client, cmd, timeout \\ 5_000) when is_integer(cmd) do
    Connection.await(client, [cmd: cmd], timeout)
  end

  @doc "等待指定 `seq` 的 Packet。"
  @spec await_seq(pid(), non_neg_integer(), timeout()) :: {:ok, Packet.t()} | {:error, term()}
  def await_seq(client, seq, timeout \\ 5_000) when is_integer(seq) do
    Connection.await(client, [seq: seq], timeout)
  end

  @doc "等待 `CMD_MSG_PUSH`（或自定义 push cmd）。"
  @spec assert_push(pid(), keyword()) :: {:ok, Packet.t()} | {:error, term()}
  def assert_push(client, opts \\ []) do
    cmd = Keyword.get(opts, :cmd, CmdType.value(:CMD_MSG_PUSH))
    timeout = Keyword.get(opts, :timeout, 5_000)
    await_cmd(client, cmd, timeout)
  end
end
