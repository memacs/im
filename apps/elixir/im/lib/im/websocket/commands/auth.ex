defmodule IM.WebSocket.Commands.Auth do
  @moduledoc "`CMD_AUTH_REQ` 薄适配：解码 → Services.Auth → AUTH_RESP / ERROR。"

  require IM.Log

  alias IM.Connection.Registry
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, ErrorCodes, Reply}
  alias IM.Services.{Auth, Kick}
  alias IM.Stores.UserDeviceStore
  alias IM.Telemetry.Connection, as: ConnTelemetry
  alias IM.Telemetry.Websocket, as: WsTelemetry
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{AuthReq, CmdType, Packet}

  @doc """
  处理鉴权命令。

  ## 示例

      IM.WebSocket.Commands.Auth.handle(packet, state)
  """
  @spec handle(Packet.t(), ConnectionState.t()) ::
          {:reply, binary(), ConnectionState.t()}
          | {:reply_close, binary(), ConnectionState.t()}
          | {:stop, ConnectionState.t()}
  def handle(%Packet{} = packet, %ConnectionState{} = state) do
    trace_id = if packet.trace_id == "", do: Ecto.UUID.generate(), else: packet.trace_id

    case Codec.decode_payload(packet, AuthReq) do
      {:ok, %AuthReq{} = req} ->
        case Auth.authenticate(req, trace_id) do
          {:ok, %{resp: resp, context: ctx, kick_oldest: kick} = result} ->
            maybe_kick_oldest(kick)

            platform = to_string(ctx.platform || "unknown")
            :ok = Registry.register(ctx.app_key, ctx.user_id, ctx.device_id, platform)
            :ok = IM.UserTracker.track(ctx.app_key, ctx.user_id, ctx.device_id, %{platform: platform})
            _ = UserDeviceStore.set_online(ctx.app_key, ctx.user_id, ctx.device_id, true)
            _ = IM.EventBus.Session.login(ctx)

            new_state =
              ConnectionState.authenticate(state, ctx,
                compression: Map.get(result, :compression, :none),
                token_expires_at: Map.get(result, :token_expires_at)
              )

            case Reply.ok(packet, :CMD_AUTH_RESP, resp) do
              {:ok, out} ->
                {:ok, bin} = Codec.encode(out)
                WsTelemetry.frame_out(byte_size(bin), out.cmd)
                ConnTelemetry.auth(:success)

                IM.Audit.record(:auth_login,
                  app_key: ctx.app_key,
                  user_id: ctx.user_id,
                  device_id: ctx.device_id,
                  strategy: "token",
                  result: :success
                )

                {:reply, bin, new_state}

              {:error, _} ->
                ConnTelemetry.auth(:failure)
                {:stop, ConnectionState.closing(state)}
            end

          {:error, %Error{} = err} ->
            reason = err.msg || Atom.to_string(err.code)

            IM.Log.warning(:auth_failed,
              reason: reason,
              app_key: blank_to_nil(req.app_key),
              user_id: blank_to_nil(req.user_id)
            )

            ConnTelemetry.auth(:failure)

            IM.Audit.record(:auth_failed,
              app_key: blank_to_nil(req.app_key),
              user_id: blank_to_nil(req.user_id),
              device_id: blank_to_nil(req.device_id),
              strategy: "token",
              result: :failure,
              reason: reason
            )

            reply_auth_error(packet, state, err)
        end

      {:error, %Error{} = err} ->
        IM.Log.error(:packet_decode_error, reason: err.msg || "auth_payload_decode_failed")
        ConnTelemetry.auth(:failure)
        reply_auth_error(packet, state, err)
    end
  end

  defp reply_auth_error(packet, state, %Error{} = err) do
    err = %{err | ref_cmd: CmdType.value(:CMD_AUTH_REQ)}
    WsTelemetry.packet_error(ErrorCodes.to_int(err.code), :CMD_AUTH_REQ)

    case Reply.error(packet, err) do
      {:ok, out} ->
        {:ok, bin} = Codec.encode(out)
        WsTelemetry.frame_out(byte_size(bin), out.cmd)
        {:reply_close, bin, ConnectionState.closing(state)}

      {:error, _} ->
        {:stop, ConnectionState.closing(state)}
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp maybe_kick_oldest(nil), do: :ok

  defp maybe_kick_oldest({app_key, user_id, device_id}) do
    Kick.kick_device(app_key, user_id, device_id,
      reason: "device_limit",
      reason_code: :KICK_REASON_DEVICE_LIMIT,
      clear_local_data: false
    )
  end
end
