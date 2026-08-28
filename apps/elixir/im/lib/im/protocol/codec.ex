defmodule IM.Protocol.Codec do
  @moduledoc """
  WS 帧与生成的 Packet message（Pb.Im.Protocol.Packet）之间的编解码，
  含版本校验与 payload 压缩处理。

  生成的 message 模块在 `lib/pb/`（由 `mise run proto-gen` 产出）。
  协议语义见仓库根 `docs/design/protocol/protocol.md`。

  P0-05 骨架：Packet 的裸编解码已由 protobuf 生成物提供（见 `test/pb/protocol_pb_test.exs`），
  本模块负责其上的版本门禁、压缩与错误映射，在 P1 落地。
  """

  alias IM.Domain.Error

  @doc """
  解码一个 WS 二进制帧为 `Packet`，并校验 `ver` 与压缩算法。
  """
  @spec decode(binary()) :: {:ok, struct()} | {:error, Error.t()}
  def decode(frame) when is_binary(frame) do
    {:error, Error.not_implemented()}
  end

  @doc """
  将 `Packet` 编码为可下发的 WS 二进制帧，必要时按会话协商结果压缩 payload。
  """
  @spec encode(map() | struct()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(packet) when is_map(packet) do
    {:error, Error.not_implemented()}
  end
end
