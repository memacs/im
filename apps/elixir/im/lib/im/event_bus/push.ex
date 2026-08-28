defmodule IM.EventBus.Push do
  @moduledoc """
  离线移动推送旁路 → `im.push`（P9-03c）。

  按 `msg_id` 聚合 targets；单批上限 500。
  """

  alias IM.EventBus

  @batch_max 500

  @doc """
  发布推送批次。`targets` 为 `%{user_id, device_id, platform, push_token}` 列表。

  ## 示例

      :ok = IM.EventBus.Push.publish_batch("mid", targets)
  """
  @spec publish_batch(String.t(), [map()], keyword()) :: :ok
  def publish_batch(msg_id, targets, opts \\ [])
      when is_binary(msg_id) and is_list(targets) do
    targets
    |> Enum.chunk_every(@batch_max)
    |> Enum.each(fn chunk ->
      EventBus.publish(
        :push,
        %{
          msg_id: msg_id,
          targets: slim(chunk),
          app_key: Keyword.get(opts, :app_key),
          conv_id: Keyword.get(opts, :conv_id)
        },
        opts
      )
    end)

    :ok
  end

  defp slim(targets) do
    Enum.map(targets, fn t ->
      %{
        user_id: t[:user_id] || t.user_id,
        device_id: t[:device_id] || t.device_id,
        platform: t[:platform] || Map.get(t, :platform),
        push_token: t[:push_token] || Map.get(t, :push_token)
      }
    end)
  end
end
