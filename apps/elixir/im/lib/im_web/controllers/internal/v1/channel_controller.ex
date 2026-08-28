defmodule IMWeb.Internal.V1.ChannelController do
  @moduledoc "内部下行广播：`POST /internal/v1/channels/:namespace/:name/publish`。"

  use IMWeb, :controller

  action_fallback(IMWeb.FallbackController)

  alias IM.Application.Dispatch
  alias IM.Domain.{Error, MessageContext}

  @doc """
  后端向 Channel 订阅者广播（经 Dispatch）。
  """
  def publish(conn, %{"namespace" => ns, "name" => name} = params) do
    channel_id = "#{ns}:#{name}"
    app_key = Map.get(params, "app_key") || ""

    ctx =
      MessageContext.from_http_internal(%{
        app_key: app_key,
        user_id: "system",
        device_id: "internal",
        trace_id: conn.assigns[:trace_id] || "",
        caller_service: conn.assigns[:caller_service],
        client_ip: conn.assigns[:client_ip],
        node: node()
      })

    attrs = %{
      channel_id: channel_id,
      app_key: app_key,
      content_type: Map.get(params, "content_type", "application/json"),
      payload: Map.get(params, "payload"),
      trace_id: ctx.trace_id,
      caller_service: ctx.caller_service
    }

    case Dispatch.execute(:channel_publish_down, attrs, ctx) do
      {:ok, result} ->
        json(conn, %{
          event_id: result.event_id,
          channel_id: result.channel_id,
          accepted: true
        })

      {:error, %Error{} = err} ->
        {:error, err}
    end
  end
end
