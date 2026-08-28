defmodule IM.Protocol.Push do
  @moduledoc """
  构造服务端主动下推的 `Packet`。推送包 `seq = 0`（`seq` 只用于客户端请求-响应匹配），
  `trace_id` 应继承触发它的根请求（见 message-context / protocol §3）。
  """

  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Cmd}
  alias Pb.Im.Protocol.Packet

  @doc """
  构造推送包。`cmd` 为 `CMD_MSG_PUSH` 等推送类命令字（原子或数值）。

  ## Options

  - `:trace_id` — 根请求 trace（默认 `""`）
  - `:route_key` — 路由键（默认 `""`）
  - `:cid` — 可选幂等/关联 id（默认 `""`）
  - `:ts` — 毫秒时间戳（默认当前时间）

  ## 示例

      msg = %Pb.Im.Protocol.ChatMessage{msg_id: "m1", from: "a", to: "b"}
      {:ok, packet} = IM.Protocol.Push.build(:CMD_MSG_PUSH, msg, trace_id: "t")
      packet.seq == 0
  """
  @spec build(atom() | non_neg_integer(), binary() | struct(), keyword()) ::
          {:ok, Packet.t()} | {:error, Error.t()}
  def build(cmd, payload, opts \\ [])

  def build(cmd, payload, opts) when is_list(opts) do
    with {:ok, cmd_value} <- normalize_cmd(cmd),
         {:ok, payload_bin} <- normalize_payload(payload) do
      {:ok,
       %Packet{
         ver: 1,
         cmd: cmd_value,
         seq: 0,
         ts: Keyword.get(opts, :ts, System.system_time(:millisecond)),
         cid: Keyword.get(opts, :cid, ""),
         trace_id: Keyword.get(opts, :trace_id, ""),
         route_key: Keyword.get(opts, :route_key, ""),
         payload: payload_bin,
         compression: :PAYLOAD_COMPRESSION_NONE
       }}
    end
  end

  defp normalize_cmd(cmd) when is_integer(cmd) and cmd >= 0, do: {:ok, cmd}
  defp normalize_cmd(cmd) when is_atom(cmd), do: Cmd.to_value(cmd)

  defp normalize_payload(payload) when is_binary(payload), do: {:ok, payload}
  defp normalize_payload(%_{} = payload), do: Codec.encode_payload(payload)
  defp normalize_payload(_), do: {:error, Error.new(:msg_invalid, "invalid push payload")}
end
