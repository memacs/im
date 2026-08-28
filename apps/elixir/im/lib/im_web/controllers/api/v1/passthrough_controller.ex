defmodule IMWeb.Api.V1.PassthroughController do
  @moduledoc "透传 REST（与 WS `CMD_PASSTHROUGH` 同 Dispatch）。"

  use IMWeb, :controller

  action_fallback(IMWeb.FallbackController)

  alias IM.Application.Dispatch
  alias IM.Domain.Error
  alias IMWeb.Api.V1.Json
  alias Pb.Im.Protocol.{CmdType, Passthrough}

  def create(conn, params) do
    ctx = conn.assigns.message_context
    cmd = CmdType.value(:CMD_PASSTHROUGH)

    pt = %Passthrough{
      chat_type: chat_type(params),
      from: ctx.user_id,
      to: Json.str(params, "to"),
      action: Json.str(params, "action"),
      data: data_bin(params),
      persist: truthy?(params, "persist"),
      conv_id: Json.str(params, "conv_id"),
      ttl_sec: Json.int(params, "ttl_sec", 0)
    }

    case Dispatch.execute(cmd, pt, ctx) do
      {:ok, %{passthrough: out}} ->
        json(conn, %{
          ok: true,
          to: out.to,
          action: out.action,
          chat_type: to_string(out.chat_type)
        })

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  defp chat_type(params) do
    case Map.get(params, "chat_type") || Map.get(params, :chat_type) do
      "CHAT_GROUP" -> :CHAT_GROUP
      "group" -> :CHAT_GROUP
      2 -> :CHAT_GROUP
      "2" -> :CHAT_GROUP
      _ -> :CHAT_PRIVATE
    end
  end

  defp data_bin(params) do
    case Map.get(params, "data") || Map.get(params, :data) || Map.get(params, "payload") do
      nil -> <<>>
      bin when is_binary(bin) -> bin
      other -> Jason.encode!(other)
    end
  end

  defp truthy?(params, key) do
    case Map.get(params, key) || Map.get(params, String.to_atom(key)) do
      true -> true
      "true" -> true
      1 -> true
      _ -> false
    end
  end
end
