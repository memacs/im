defmodule IM.Protocol.Cmd do
  @moduledoc """
  `CmdType` 枚举数值与原子的互转，以及命令分区判定（连接/消息/ACK/…，区间约定见
  `proto/common.proto` 的 `CmdType` 注释）。

  实现委托给生成的 CmdType enum（Pb.Im.Protocol.CmdType），本模块只提供不会因未知数值崩溃的安全封装：
  老服务端收到新客户端的未知 cmd 时必须优雅拒绝，而不是 raise。

  P0-05 骨架：随 `IM.Protocol.Router` 在 P1 落地。
  """

  alias IM.Domain.Error

  @doc """
  数值 → 原子。未知数值返回错误而非 raise。
  """
  @spec to_atom(non_neg_integer()) :: {:ok, atom()} | {:error, Error.t()}
  def to_atom(cmd) when is_integer(cmd) do
    {:error, Error.not_implemented(cmd)}
  end

  @doc """
  原子 → 数值。
  """
  @spec to_value(atom()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def to_value(cmd) when is_atom(cmd) do
    {:error, Error.not_implemented()}
  end
end
