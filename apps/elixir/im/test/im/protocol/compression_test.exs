defmodule IM.Protocol.CompressionTest do
  use ExUnit.Case, async: true

  alias IM.Protocol.{Codec, Compression}
  alias Pb.Im.Protocol.{CmdType, HeartbeatReq, Packet, PayloadCompression}

  test "negotiate 优先 GZIP" do
    assert :PAYLOAD_COMPRESSION_GZIP =
             Compression.negotiate([:PAYLOAD_COMPRESSION_GZIP, :PAYLOAD_COMPRESSION_NONE])
  end

  test "gzip 往返" do
    raw = "hello-compression"
    assert {:ok, z} = Compression.compress(raw, :PAYLOAD_COMPRESSION_GZIP)
    assert z != raw
    assert {:ok, ^raw} = Compression.decompress(z, :PAYLOAD_COMPRESSION_GZIP)
  end

  test "NONE / UNSPECIFIED / 整数枚举" do
    raw = "plain"

    assert {:ok, ^raw} = Compression.compress(raw, :PAYLOAD_COMPRESSION_NONE)
    assert {:ok, ^raw} = Compression.decompress(raw, :PAYLOAD_COMPRESSION_NONE)
    assert {:ok, ^raw} = Compression.compress(raw, :PAYLOAD_COMPRESSION_UNSPECIFIED)
    assert {:ok, "bad"} = Compression.decompress("bad", :PAYLOAD_COMPRESSION_LZ4)

    assert :PAYLOAD_COMPRESSION_NONE =
             Compression.negotiate([:PAYLOAD_COMPRESSION_NONE, :PAYLOAD_COMPRESSION_GZIP])

    assert :PAYLOAD_COMPRESSION_GZIP =
             Compression.negotiate([PayloadCompression.value(:PAYLOAD_COMPRESSION_GZIP)])
  end

  test "无效 gzip 返回 error" do
    assert {:error, _} = Compression.decompress(<<0, 1, 2>>, :PAYLOAD_COMPRESSION_GZIP)
  end

  test "Codec encode/decode 带 GZIP" do
    body = %HeartbeatReq{client_time: 1}
    {:ok, payload} = Codec.encode_payload(body)

    packet = %Packet{
      ver: 1,
      cmd: CmdType.value(:CMD_HEARTBEAT_REQ),
      seq: 9,
      compression: :PAYLOAD_COMPRESSION_GZIP,
      payload: payload
    }

    assert {:ok, bin} = Codec.encode(packet)
    assert {:ok, decoded} = Codec.decode(bin)
    assert decoded.compression == :PAYLOAD_COMPRESSION_GZIP
    assert decoded.payload == payload
  end
end
