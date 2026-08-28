defmodule IM.Log.Metadata do
  @moduledoc """
  请求入口 Logger.metadata 注入（Packet / 连接上下文）。
  """

  require Logger

  alias IM.Protocol.Cmd
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.Packet

  @doc """
  从 Packet 与连接状态写入链路 metadata，返回可用的 `trace_id`。

  ## 示例

      trace_id = IM.Log.Metadata.set_from_packet(packet, state)
  """
  @spec set_from_packet(Packet.t(), ConnectionState.t()) :: String.t()
  def set_from_packet(%Packet{} = packet, %ConnectionState{} = state) do
    trace_id =
      case packet.trace_id do
        tid when is_binary(tid) and tid != "" -> tid
        _ -> Ecto.UUID.generate()
      end

    base = [
      trace_id: trace_id,
      cmd: cmd_name(packet.cmd),
      seq: packet.seq,
      cid: packet.cid
    ]

    ctx_meta =
      case state.context do
        %{app_key: a, user_id: u, device_id: d, session_id: s} ->
          [app_key: a, user_id: u, device_id: d, session_id: s]

        _ ->
          []
      end

    put(base ++ ctx_meta)
    trace_id
  end

  @doc """
  写入非 nil metadata 键。

  ## 示例

      IM.Log.Metadata.put(trace_id: "t1", app_key: "demo")
  """
  @spec put(keyword() | map()) :: :ok
  def put(kv) when is_list(kv) do
    kv
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Logger.metadata()

    :ok
  end

  def put(kv) when is_map(kv), do: put(Map.to_list(kv))

  @doc """
  清空当前进程 Logger metadata。

  ## 示例

      IM.Log.Metadata.clear()
  """
  @spec clear() :: :ok
  def clear do
    Logger.metadata([])
    :ok
  end

  defp cmd_name(cmd) do
    case Cmd.to_atom(cmd) do
      {:ok, atom} -> Atom.to_string(atom)
      _ -> Integer.to_string(cmd)
    end
  end
end
