defmodule IM.WebSocket.Commands.Group.Create do
  @moduledoc "`CMD_GROUP_CREATE_REQ`。"

  alias IM.Application.Dispatch
  alias IM.Delivery.Router
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Push}
  alias IM.WebSocket.Commands.Group.Helpers
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, GroupCreateReq, Packet}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %GroupCreateReq{} = req} <- Codec.decode_payload(packet, GroupCreateReq),
         {:ok, result} <-
           Dispatch.execute(CmdType.value(:CMD_GROUP_CREATE_REQ), req, ctx) do
      if result.join_push do
        case Push.build(:CMD_GROUP_JOIN_PUSH, result.join_push,
               trace_id: packet.trace_id,
               route_key: result.resp.group_id
             ) do
          {:ok, out} ->
            Enum.each(result.notify_user_ids, fn uid ->
              _ = Router.push_packet(out, ctx.app_key, uid)
            end)

          _ ->
            :ok
        end
      end

      Helpers.reply_resp(packet, state, :CMD_GROUP_CREATE_RESP, result.resp)
    else
      {:error, %Error{} = err} ->
        Helpers.reply_error(packet, state, err, CmdType.value(:CMD_GROUP_CREATE_REQ))
    end
  end

  def handle(_packet, state), do: Helpers.unauth_stop(state)
end
