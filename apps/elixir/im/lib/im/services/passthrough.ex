defmodule IM.Services.Passthrough do
  @moduledoc "透传与流式透传模式（P7-05/P7-07）。"

  alias IM.Domain.{Error, MessageContext}
  alias IM.Stores.PassthroughStore
  alias Pb.Im.Protocol.Passthrough

  @stream_actions ~w(stream_start stream_chunk stream_end stream_cancel)

  @doc """
  发送透传；可选落库；返回推送目标。
  """
  @spec send(Passthrough.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def send(%Passthrough{} = pt, %MessageContext{} = ctx) do
    from = if pt.from == "", do: ctx.user_id, else: pt.from

    cond do
      from != ctx.user_id ->
        {:error, Error.new(:msg_invalid, "from mismatch")}

      pt.to == "" ->
        {:error, Error.new(:msg_invalid, "to required")}

      true ->
        normalized = %{pt | from: from}
        maybe_persist(normalized, ctx)

        targets =
          case pt.chat_type do
            :CHAT_PRIVATE -> [pt.to]
            1 -> [pt.to]
            :CHAT_GROUP -> IM.Group.MemberCache.list_member_ids(ctx.app_key, pt.to)
            2 -> IM.Group.MemberCache.list_member_ids(ctx.app_key, pt.to)
            _ -> [pt.to]
          end

        # 发送方其他设备也收（流式同步）
        recipients = Enum.uniq([from | targets])

        {:ok,
         %{
           passthrough: normalized,
           recipient_user_ids: recipients,
           exclude_device_id: ctx.device_id,
           stream?: pt.action in @stream_actions
         }}
    end
  end

  defp maybe_persist(%Passthrough{persist: true} = pt, ctx) do
    ttl = clamp_ttl(pt.ttl_sec)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    expires = DateTime.add(now, ttl, :second)

    # 为每个目标用户存一份（含发送方多端补推）
    for uid <- Enum.uniq([ctx.user_id, pt.to]) do
      _ =
        PassthroughStore.insert(%{
          app_key: ctx.app_key,
          user_id: uid,
          from_uid: pt.from,
          to_id: pt.to,
          chat_type: chat_type_int(pt.chat_type),
          conv_id: pt.conv_id,
          action: pt.action || "",
          data: pt.data || <<>>,
          expires_at: expires,
          created_at: now
        })
    end

    :ok
  end

  defp maybe_persist(_, _), do: :ok

  defp clamp_ttl(n) when is_integer(n) and n > 0, do: min(n, 7 * 24 * 3600)
  defp clamp_ttl(_), do: 7 * 24 * 3600

  defp chat_type_int(:CHAT_PRIVATE), do: 1
  defp chat_type_int(:CHAT_GROUP), do: 2
  defp chat_type_int(:CHAT_ROOM), do: 3
  defp chat_type_int(n) when is_integer(n), do: n
  defp chat_type_int(_), do: 1
end
