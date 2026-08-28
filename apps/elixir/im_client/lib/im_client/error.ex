defmodule IM.Client.Error do
  @moduledoc "客户端侧轻量错误（不依赖服务端 Domain.Error）。"

  defstruct [:code, :msg, :packet]

  @type t :: %__MODULE__{
          code: atom(),
          msg: String.t() | nil,
          packet: Pb.Im.Protocol.Packet.t() | nil
        }

  @spec new(atom(), String.t() | nil, keyword()) :: t()
  def new(code, msg \\ nil, opts \\ []) when is_atom(code) do
    %__MODULE__{code: code, msg: msg, packet: Keyword.get(opts, :packet)}
  end
end
