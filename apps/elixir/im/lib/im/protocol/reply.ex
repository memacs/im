defmodule IM.Protocol.Reply do
  @moduledoc """
  由请求 `Packet` 构造响应 `Packet`：继承 `seq`、`trace_id`、`cid`，填对应的响应 `cmd`。

  失败响应统一走 `error/2` 生成 `CMD_ERROR` + `ErrorBody`；成功响应不带错误码
  （见 `docs/design/protocol/protocol.md` §3）。
  """

  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Cmd, ErrorCodes}
  alias Pb.Im.Protocol.{CmdType, ErrorBody, Packet}

  @doc """
  构造成功响应，继承请求包的 `seq` / `trace_id` / `cid`。

  `resp_cmd` 可为 `CmdType` 原子或数值；`payload` 可为业务结构体或已编码二进制。

  ## 示例

      req = %Pb.Im.Protocol.Packet{ver: 1, cmd: 3, seq: 9, trace_id: "t"}
      {:ok, resp} =
        IM.Protocol.Reply.ok(req, :CMD_HEARTBEAT_RESP, %Pb.Im.Protocol.HeartbeatResp{server_time: 1})
      resp.seq == 9 and resp.cmd == 4
  """
  @spec ok(Packet.t(), atom() | non_neg_integer(), binary() | struct()) ::
          {:ok, Packet.t()} | {:error, Error.t()}
  def ok(%Packet{} = request, resp_cmd, payload) do
    with {:ok, cmd} <- normalize_cmd(resp_cmd),
         {:ok, payload_bin} <- normalize_payload(payload) do
      {:ok,
       %Packet{
         ver: 1,
         cmd: cmd,
         seq: request.seq,
         ts: System.system_time(:millisecond),
         cid: request.cid,
         trace_id: request.trace_id,
         route_key: request.route_key,
         payload: payload_bin,
         compression: reply_compression(request)
       }}
    end
  end

  @doc """
  `ok/3` 的别名，兼容文档中的 `Reply.success` 命名。

  ## 示例

      {:ok, resp} = IM.Protocol.Reply.success(req, :CMD_AUTH_RESP, auth_resp_struct)
  """
  @spec success(Packet.t(), atom() | non_neg_integer(), binary() | struct()) ::
          {:ok, Packet.t()} | {:error, Error.t()}
  def success(%Packet{} = request, resp_cmd, payload), do: ok(request, resp_cmd, payload)

  @doc """
  构造 `CMD_ERROR` 响应，把 `IM.Domain.Error` 映射为 `ErrorBody`。

  ## 示例

      err = IM.Domain.Error.new(:unauthorized, "bad", ref_cmd: 1)
      {:ok, packet} = IM.Protocol.Reply.error(req, err)
      packet.cmd == 6
  """
  @spec error(Packet.t(), Error.t()) :: {:ok, Packet.t()} | {:error, Error.t()}
  def error(%Packet{} = request, %Error{} = err) do
    body = %ErrorBody{
      code: ErrorCodes.to_proto(err.code),
      msg: err.msg || "",
      ref_cmd: err.ref_cmd || request.cmd || 0,
      ref_cid: err.ref_cid || request.cid || ""
    }

    with {:ok, payload_bin} <- Codec.encode_payload(body) do
      {:ok,
       %Packet{
         ver: 1,
         cmd: CmdType.value(:CMD_ERROR),
         seq: request.seq,
         ts: System.system_time(:millisecond),
         cid: request.cid,
         trace_id: request.trace_id,
         route_key: request.route_key,
         payload: payload_bin,
         compression: :PAYLOAD_COMPRESSION_NONE
       }}
    end
  end

  defp normalize_cmd(cmd) when is_integer(cmd) and cmd >= 0, do: {:ok, cmd}

  defp normalize_cmd(cmd) when is_atom(cmd) do
    Cmd.to_value(cmd)
  end

  defp normalize_payload(payload) when is_binary(payload), do: {:ok, payload}
  defp normalize_payload(%_{} = payload), do: Codec.encode_payload(payload)
  defp normalize_payload(_), do: {:error, Error.new(:msg_invalid, "invalid reply payload")}

  # AUTH 请求/响应不压缩；其余继承请求上的 compression 字段
  defp reply_compression(%Packet{cmd: cmd}) when cmd == 1, do: :PAYLOAD_COMPRESSION_NONE

  defp reply_compression(%Packet{compression: c})
       when c in [:PAYLOAD_COMPRESSION_GZIP, :PAYLOAD_COMPRESSION_LZ4],
       do: c

  defp reply_compression(%Packet{compression: c}) when not is_nil(c), do: c
  defp reply_compression(_), do: :PAYLOAD_COMPRESSION_NONE
end
