defmodule Pb.Im.Protocol.OfflinePullReq do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:conv_id, 1, type: :string, json_name: "convId")
  field(:cursor, 2, type: :int64)
  field(:limit, 3, type: :int32)
end

defmodule Pb.Im.Protocol.OfflinePullResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:messages, 1, repeated: true, type: Pb.Im.Protocol.ChatMessage)
  field(:next_cursor, 2, type: :int64, json_name: "nextCursor")
  field(:has_more, 3, type: :bool, json_name: "hasMore")
end
