defmodule IM.Protocol.Reply do
  @moduledoc """
  由请求 `Packet` 构造响应 `Packet`：继承 `seq`、`trace_id`、`cid`，填对应的响应 `cmd`。

  失败响应统一走 `error/2` 生成 `CMD_ERROR` + `ErrorBody`，成功响应不带错误码
  （见仓库根 `docs/design/protocol/protocol.md`）。

  P0-05 骨架：待 `IM.Protocol.Codec` 与 ErrorCode 映射表就绪后在 P1 落地。
  """

  alias IM.Domain.Error

  @doc """
  构造成功响应，继承请求包的 `seq` / `trace_id` / `cid`。
  """
  @spec success(struct(), term()) :: {:ok, struct()} | {:error, Error.t()}
  def success(_request_packet, _resp_payload) do
    {:error, Error.not_implemented()}
  end

  @doc """
  构造 `CMD_ERROR` 响应，把 `IM.Domain.Error` 映射为 `ErrorBody`。
  """
  @spec error(struct(), Error.t()) :: {:ok, struct()} | {:error, Error.t()}
  def error(_request_packet, %Error{}) do
    {:error, Error.not_implemented()}
  end
end
