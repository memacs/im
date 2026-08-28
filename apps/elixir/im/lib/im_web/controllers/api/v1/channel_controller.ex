defmodule IMWeb.Api.V1.ChannelController do
  @moduledoc "客户端 REST：订阅 / 取消 / 上行（与 WS 共用 Service）。"

  use IMWeb, :controller

  action_fallback(IMWeb.FallbackController)

  alias IM.Application.Dispatch
  alias IM.Domain.Error
  alias Pb.Im.Protocol.{ChannelPublish, CmdType}

  @doc "`PUT /api/v1/channels/subscriptions`"
  def subscribe(conn, params) do
    ctx = conn.assigns.message_context
    ids = channel_ids(params)
    cmd = CmdType.value(:CMD_CHANNEL_SUBSCRIBE_REQ)

    case Dispatch.execute(cmd, %{channel_ids: ids}, ctx) do
      {:ok, resp} ->
        json(conn, %{
          subscribed: resp.subscribed,
          failed:
            Enum.map(resp.failed, fn f ->
              %{channel_id: f.channel_id, code: f.code, msg: f.msg}
            end)
        })

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  @doc "`DELETE /api/v1/channels/subscriptions`"
  def unsubscribe(conn, params) do
    ctx = conn.assigns.message_context
    ids = channel_ids(params)
    cmd = CmdType.value(:CMD_CHANNEL_UNSUBSCRIBE_REQ)

    case Dispatch.execute(cmd, %{channel_ids: ids}, ctx) do
      {:ok, resp} ->
        json(conn, %{unsubscribed: resp.unsubscribed})

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  @doc "`POST /api/v1/channels/publish`"
  def publish(conn, params) do
    ctx = conn.assigns.message_context
    cmd = CmdType.value(:CMD_CHANNEL_PUBLISH)

    req = %ChannelPublish{
      channel_id: str(params, "channel_id"),
      content_type: str(params, "content_type", "application/json"),
      payload: payload_bin(params),
      client_event_id: str(params, "client_event_id")
    }

    case Dispatch.execute(cmd, req, ctx) do
      {:ok, :drop_silent} ->
        json(conn, %{accepted: false, dropped: true})

      {:ok, ack} ->
        json(conn, %{
          channel_id: ack.channel_id,
          event_id: ack.event_id,
          accepted: ack.accepted
        })

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  defp channel_ids(params) do
    raw = Map.get(params, "channel_ids") || Map.get(params, :channel_ids) || []
    raw |> List.wrap() |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == ""))
  end

  defp str(params, key, default \\ "") do
    case Map.get(params, key) || Map.get(params, String.to_atom(key)) do
      nil -> default
      v -> to_string(v)
    end
  end

  defp payload_bin(params) do
    case Map.get(params, "payload") || Map.get(params, :payload) do
      nil -> <<>>
      bin when is_binary(bin) -> bin
      other -> Jason.encode!(other)
    end
  end
end
