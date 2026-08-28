defmodule IM.Services.Heartbeat do
  @moduledoc "`CMD_HEARTBEAT_REQ`：返回服务端时间。"

  alias IM.Domain.MessageContext
  alias Pb.Im.Protocol.{HeartbeatReq, HeartbeatResp}

  @doc """
  处理心跳。

  ## 示例

      {:ok, %HeartbeatResp{}} = IM.Services.Heartbeat.beat(%HeartbeatReq{}, ctx)
  """
  @spec beat(HeartbeatReq.t(), MessageContext.t()) :: {:ok, HeartbeatResp.t()}
  def beat(%HeartbeatReq{}, %MessageContext{} = ctx) do
    _ = IM.EventBus.Session.heartbeat(ctx)
    {:ok, %HeartbeatResp{server_time: System.system_time(:millisecond)}}
  end
end
