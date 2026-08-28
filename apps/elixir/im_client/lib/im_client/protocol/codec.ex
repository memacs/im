defmodule IM.Client.Protocol.Codec do
  @moduledoc """
  WS 帧与 `Pb.Im.Protocol.Packet` 编解码，含协议版本门禁。

  语义与服务端 `IM.Protocol.Codec` 对齐；错误类型为 `IM.Client.Error`。
  """

  alias IM.Client.Error
  alias Pb.Im.Protocol.{Packet, ProtoVersion}

  @supported_ver ProtoVersion.value(:PROTO_VERSION_V1)

  @packet_keys [
    :ver,
    :cmd,
    :seq,
    :ts,
    :cid,
    :trace_id,
    :payload,
    :route_key,
    :compression
  ]

  @doc "解码 WS 二进制帧为 Packet，并校验 `ver == 1`。"
  @spec decode(binary()) :: {:ok, Packet.t()} | {:error, Error.t()}
  def decode(frame) when is_binary(frame) do
    frame
    |> Packet.decode()
    |> validate_ver()
  rescue
    e in [Protobuf.DecodeError, ArgumentError, FunctionClauseError] ->
      {:error, Error.new(:msg_invalid, Exception.message(e))}
  end

  @doc "将 Packet（或字段 map）编码为 WS 二进制帧。"
  @spec encode(Packet.t() | map()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(%Packet{} = packet) do
    with {:ok, valid} <- validate_ver(packet) do
      {:ok, Packet.encode(valid)}
    end
  rescue
    e ->
      {:error, Error.new(:msg_invalid, Exception.message(e))}
  end

  def encode(%{} = attrs) do
    packet =
      attrs
      |> Map.take(@packet_keys)
      |> then(&struct(Packet, &1))

    encode(packet)
  end

  @doc "将业务 Protobuf 结构体编码为 `Packet.payload`。"
  @spec encode_payload(struct()) :: {:ok, binary()} | {:error, Error.t()}
  def encode_payload(%mod{} = msg) when is_atom(mod) do
    {:ok, mod.encode(msg)}
  rescue
    e ->
      {:error, Error.new(:msg_invalid, Exception.message(e))}
  end

  @doc "按 message 模块解码 `Packet.payload`。"
  @spec decode_payload(Packet.t(), module()) :: {:ok, struct()} | {:error, Error.t()}
  def decode_payload(%Packet{payload: payload}, mod) when is_atom(mod) and is_binary(payload) do
    {:ok, mod.decode(payload)}
  rescue
    e in [Protobuf.DecodeError, ArgumentError, FunctionClauseError] ->
      {:error, Error.new(:msg_invalid, Exception.message(e))}
  end

  defp validate_ver(%Packet{ver: ver} = packet) when ver == @supported_ver, do: {:ok, packet}

  defp validate_ver(%Packet{ver: ver}) do
    {:error, Error.new(:proto_version_unsupported, "unsupported protocol version: #{ver}")}
  end
end
