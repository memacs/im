defmodule IM.Protocol.Codec do
  @moduledoc """
  WS 帧与 `Pb.Im.Protocol.Packet` 之间的编解码，含协议版本门禁与 payload 压缩。
  """

  alias IM.Domain.Error
  alias IM.Protocol.Compression
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

  @doc """
  解码一个 WS 二进制帧为 `Packet`，并校验 `ver == 1`。

  ## 示例

      bin = Pb.Im.Protocol.Packet.encode(%Pb.Im.Protocol.Packet{ver: 1, cmd: 3, seq: 1})
      {:ok, %Pb.Im.Protocol.Packet{ver: 1}} = IM.Protocol.Codec.decode(bin)
  """
  @spec decode(binary()) :: {:ok, Packet.t()} | {:error, Error.t()}
  def decode(frame) when is_binary(frame) do
    with %Packet{} = packet <- Packet.decode(frame),
         {:ok, valid} <- validate_ver(packet),
         {:ok, payload} <- Compression.decompress(valid.payload || <<>>, valid.compression) do
      {:ok, %{valid | payload: payload}}
    else
      {:error, %Error{}} = err -> err
      {:error, reason} -> {:error, Error.new(:msg_invalid, "decompress: #{inspect(reason)}")}
    end
  rescue
    e in [Protobuf.DecodeError, ArgumentError, FunctionClauseError] ->
      {:error, Error.new(:msg_invalid, Exception.message(e))}
  end

  @doc """
  将 `Packet`（或字段 map）编码为可下发的 WS 二进制帧。

  ## 示例

      {:ok, bin} = IM.Protocol.Codec.encode(%Pb.Im.Protocol.Packet{ver: 1, cmd: 3})
      is_binary(bin) # => true
  """
  @spec encode(Packet.t() | map()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(%Packet{} = packet) do
    with {:ok, valid} <- validate_ver(packet),
         {:ok, payload} <- Compression.compress(valid.payload || <<>>, valid.compression) do
      {:ok, Packet.encode(%{valid | payload: payload})}
    else
      {:error, %Error{}} = err -> err
      {:error, reason} -> {:error, Error.new(:msg_invalid, "compress: #{inspect(reason)}")}
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

  @doc """
  将业务 Protobuf 结构体编码为 `Packet.payload` 字节。

  ## 示例

      {:ok, bin} = IM.Protocol.Codec.encode_payload(%Pb.Im.Protocol.HeartbeatResp{server_time: 1})
  """
  @spec encode_payload(struct()) :: {:ok, binary()} | {:error, Error.t()}
  def encode_payload(%mod{} = msg) when is_atom(mod) do
    {:ok, mod.encode(msg)}
  rescue
    e ->
      {:error, Error.new(:msg_invalid, Exception.message(e))}
  end

  @doc """
  按 message 模块解码 `Packet.payload`。

  ## 示例

      {:ok, bytes} = IM.Protocol.Codec.encode_payload(%Pb.Im.Protocol.HeartbeatResp{server_time: 9})
      packet = %Pb.Im.Protocol.Packet{payload: bytes}
      {:ok, %Pb.Im.Protocol.HeartbeatResp{server_time: 9}} =
        IM.Protocol.Codec.decode_payload(packet, Pb.Im.Protocol.HeartbeatResp)
  """
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
