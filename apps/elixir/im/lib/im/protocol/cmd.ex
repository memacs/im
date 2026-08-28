defmodule IM.Protocol.Cmd do
  @moduledoc """
  `CmdType` 枚举数值与原子的互转。

  实现委托给生成的 `Pb.Im.Protocol.CmdType`；未知数值返回错误而非 raise，
  以便老服务端优雅拒绝新客户端的未知 cmd。
  """

  alias IM.Domain.Error
  alias Pb.Im.Protocol.CmdType

  @doc """
  数值 → 原子。未知数值返回 `{:error, %Error{code: :unknown_cmd}}`。

  ## 示例

      {:ok, :CMD_MSG_SEND} = IM.Protocol.Cmd.to_atom(100)
      {:error, %{code: :unknown_cmd}} = IM.Protocol.Cmd.to_atom(65_535)
  """
  @spec to_atom(non_neg_integer()) :: {:ok, atom()} | {:error, Error.t()}
  def to_atom(cmd) when is_integer(cmd) and cmd >= 0 do
    # protobuf_elixir：未知枚举值的 key/1 会原样返回整数，而非 nil
    case CmdType.key(cmd) do
      atom when is_atom(atom) ->
        {:ok, atom}

      _other ->
        {:error, Error.new(:unknown_cmd, "unknown cmd: #{cmd}", ref_cmd: cmd)}
    end
  end

  @doc """
  原子 → 数值。未知原子返回错误。

  ## 示例

      {:ok, 100} = IM.Protocol.Cmd.to_value(:CMD_MSG_SEND)
  """
  @spec to_value(atom()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def to_value(cmd) when is_atom(cmd) do
    try do
      {:ok, CmdType.value(cmd)}
    rescue
      FunctionClauseError ->
        {:error, Error.new(:unknown_cmd, "unknown cmd atom: #{cmd}")}
    end
  end
end
