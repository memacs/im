defmodule Pb.Im.Protocol.Passthrough do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:chat_type, 1, type: Pb.Im.Protocol.ChatType, json_name: "chatType", enum: true)
  field(:from, 2, type: :string)
  field(:to, 3, type: :string)
  field(:action, 4, type: :string)
  field(:data, 5, type: :bytes)
  field(:persist, 6, type: :bool)
  field(:conv_id, 7, type: :string, json_name: "convId")
  field(:ttl_sec, 8, type: :int32, json_name: "ttlSec")
end
