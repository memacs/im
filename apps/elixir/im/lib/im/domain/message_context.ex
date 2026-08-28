defmodule IM.Domain.MessageContext do
  @moduledoc """
  一次请求的身份与链路上下文，贯穿 WS、REST、内部 API、Kafka。

  见 `docs/design/message-context.md`、`dual-channel-api.md` §4.4。
  """

  @enforce_keys [:app_key, :user_id, :device_id, :trace_id]

  defstruct [
    :app_key,
    :user_id,
    :device_id,
    :session_id,
    :platform,
    :trace_id,
    :node,
    :connected_at,
    :caller_service,
    :client_ip,
    source: :websocket,
    write_kafka: true,
    run_hooks: true,
    push_online: true,
    store_offline: true,
    started_at: nil,
    metadata: %{}
  ]

  @type source :: :websocket | :http_client | :http_internal | :kafka | :system

  @type t :: %__MODULE__{
          app_key: String.t(),
          user_id: String.t(),
          device_id: String.t(),
          session_id: String.t() | nil,
          platform: atom() | nil,
          trace_id: String.t(),
          node: node() | nil,
          connected_at: DateTime.t() | nil,
          source: source(),
          caller_service: String.t() | nil,
          client_ip: String.t() | nil,
          write_kafka: boolean(),
          run_hooks: boolean(),
          push_online: boolean(),
          store_offline: boolean(),
          started_at: integer() | nil,
          metadata: map()
        }

  @doc """
  WebSocket 鉴权后构造。

  ## 示例

      IM.Domain.MessageContext.from_websocket(%{app_key: "a", user_id: "u", device_id: "d", trace_id: "t"})
  """
  @spec from_websocket(map()) :: t()
  def from_websocket(attrs) when is_map(attrs) do
    build(attrs, :websocket)
  end

  @doc """
  客户端 REST（Bearer）构造。

  ## 示例

      IM.Domain.MessageContext.from_http_client(%{app_key: "a", user_id: "u", device_id: "d", trace_id: "t"})
  """
  @spec from_http_client(map()) :: t()
  def from_http_client(attrs) when is_map(attrs) do
    build(attrs, :http_client)
  end

  @doc """
  内部 REST 构造（`caller_service` 必填语义由 Plug 保证）。

  ## 示例

      IM.Domain.MessageContext.from_http_internal(%{
        app_key: "a", user_id: "u", device_id: "internal",
        trace_id: "t", caller_service: "ops"
      })
  """
  @spec from_http_internal(map()) :: t()
  def from_http_internal(attrs) when is_map(attrs) do
    build(attrs, :http_internal)
  end

  defp build(attrs, source) do
    %__MODULE__{
      app_key: Map.fetch!(attrs, :app_key),
      user_id: Map.fetch!(attrs, :user_id),
      device_id: Map.fetch!(attrs, :device_id),
      trace_id: Map.fetch!(attrs, :trace_id),
      session_id: Map.get(attrs, :session_id),
      platform: Map.get(attrs, :platform),
      node: Map.get(attrs, :node, node()),
      connected_at: Map.get(attrs, :connected_at),
      source: source,
      caller_service: Map.get(attrs, :caller_service),
      client_ip: Map.get(attrs, :client_ip),
      write_kafka: Map.get(attrs, :write_kafka, true),
      run_hooks: Map.get(attrs, :run_hooks, true),
      push_online: Map.get(attrs, :push_online, true),
      store_offline: Map.get(attrs, :store_offline, true),
      started_at: Map.get(attrs, :started_at, System.system_time(:millisecond)),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
