defmodule IM.Log do
  @moduledoc """
  结构化日志的统一入口：把 `MessageContext` 的链路字段放进 Logger metadata，
  让同一请求在 WS、Service、Kafka 各段日志里能用 `trace_id` 串起来。

  直接调用 `Logger` 也能出日志，但拼在消息字符串里的字段无法被日志后端索引，
  排障时只能全文搜索 —— 所以链路字段一律走 metadata。
  """

  require Logger

  alias IM.Domain.MessageContext

  @doc """
  把上下文写入当前进程的 Logger metadata，后续该进程的所有日志自动带上这些字段。

  在 WS 连接进程 / Plug 入口调用一次即可，无需逐条日志重复传。
  """
  @spec put_context(MessageContext.t()) :: :ok
  def put_context(%MessageContext{} = ctx) do
    Logger.metadata(
      trace_id: ctx.trace_id,
      app_key: ctx.app_key,
      user_id: ctx.user_id,
      device_id: ctx.device_id,
      session_id: ctx.session_id
    )
  end

  @doc """
  返回当前进程已记录的链路字段，便于跨进程传递（如投递到 Task 或 GenServer 前）。
  """
  @spec context_metadata() :: keyword()
  def context_metadata do
    Logger.metadata()
    |> Keyword.take([:trace_id, :app_key, :user_id, :device_id, :session_id])
  end
end
