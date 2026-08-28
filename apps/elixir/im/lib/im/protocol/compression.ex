defmodule IM.Protocol.Compression do
  @moduledoc "Packet.payload 压缩协商与编解码（GZIP；LZ4 预留）。"

  alias Pb.Im.Protocol.PayloadCompression

  @doc """
  协商算法。服务端允许列表默认含 NONE 与 GZIP（可配）。
  """
  @spec negotiate([atom() | integer()], String.t() | nil) :: atom()
  def negotiate(offered, _app_key \\ nil) do
    client = normalize_list(offered)
    server = allowed()
    Enum.find(client, &(&1 in server)) || :PAYLOAD_COMPRESSION_NONE
  end

  @doc "压缩 payload；NONE 原样返回。"
  @spec compress(binary(), atom()) :: {:ok, binary()} | {:error, term()}
  def compress(payload, :PAYLOAD_COMPRESSION_NONE) when is_binary(payload), do: {:ok, payload}

  def compress(payload, :PAYLOAD_COMPRESSION_UNSPECIFIED) when is_binary(payload),
    do: {:ok, payload}

  def compress(payload, :PAYLOAD_COMPRESSION_GZIP) when is_binary(payload) do
    {:ok, :zlib.gzip(payload)}
  rescue
    e -> {:error, e}
  end

  def compress(payload, other) when is_binary(payload) do
    case to_atom(other) do
      :PAYLOAD_COMPRESSION_GZIP -> compress(payload, :PAYLOAD_COMPRESSION_GZIP)
      _ -> {:ok, payload}
    end
  end

  @doc "解压 payload。"
  @spec decompress(binary(), atom()) :: {:ok, binary()} | {:error, term()}
  def decompress(payload, :PAYLOAD_COMPRESSION_NONE) when is_binary(payload), do: {:ok, payload}

  def decompress(payload, :PAYLOAD_COMPRESSION_UNSPECIFIED) when is_binary(payload),
    do: {:ok, payload}

  def decompress(payload, :PAYLOAD_COMPRESSION_GZIP) when is_binary(payload) do
    {:ok, :zlib.gunzip(payload)}
  rescue
    e -> {:error, e}
  end

  def decompress(payload, other) when is_binary(payload) do
    case to_atom(other) do
      :PAYLOAD_COMPRESSION_GZIP -> decompress(payload, :PAYLOAD_COMPRESSION_GZIP)
      _ -> {:ok, payload}
    end
  end

  @doc "枚举原子 → AuthResp 字段。"
  def to_proto_enum(atom) when is_atom(atom), do: atom

  defp allowed do
    Application.get_env(:im, :allowed_payload_compressions, [
      :PAYLOAD_COMPRESSION_GZIP,
      :PAYLOAD_COMPRESSION_NONE
    ])
  end

  defp normalize_list(list) when is_list(list) do
    list
    |> Enum.map(&to_atom/1)
    |> Enum.reject(&(&1 == :PAYLOAD_COMPRESSION_UNSPECIFIED))
  end

  defp normalize_list(_), do: []

  defp to_atom(:PAYLOAD_COMPRESSION_GZIP), do: :PAYLOAD_COMPRESSION_GZIP
  defp to_atom(:PAYLOAD_COMPRESSION_NONE), do: :PAYLOAD_COMPRESSION_NONE
  defp to_atom(:PAYLOAD_COMPRESSION_LZ4), do: :PAYLOAD_COMPRESSION_LZ4
  defp to_atom(:gzip), do: :PAYLOAD_COMPRESSION_GZIP
  defp to_atom(:none), do: :PAYLOAD_COMPRESSION_NONE
  defp to_atom(:lz4), do: :PAYLOAD_COMPRESSION_LZ4

  defp to_atom(n) when is_integer(n) do
    case PayloadCompression.key(n) do
      atom when is_atom(atom) -> atom
      _ -> :PAYLOAD_COMPRESSION_NONE
    end
  end

  defp to_atom(_), do: :PAYLOAD_COMPRESSION_NONE
end
