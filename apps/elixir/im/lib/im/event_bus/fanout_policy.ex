defmodule IM.EventBus.FanoutPolicy do
  @moduledoc """
  下行 Kafka 扇出模式判定（P9-03b）。

  - 单聊：`:direct`
  - 群：成员数 > 阈值 → `:group_aggregated`，否则 `:direct`
  - 聊天室：默认 `:room_aggregated`
  """

  alias IM.Group.MetaCache

  @type mode :: :direct | :group_aggregated | :room_aggregated

  @doc """
  解析扇出模式。

  ## 示例

      {:direct, nil} = IM.EventBus.FanoutPolicy.resolve(%{chat_type: :CHAT_PRIVATE}, [])
  """
  @spec resolve(map(), list()) :: {mode(), nil}
  def resolve(%{chat_type: type}, _targets) when type in [:CHAT_PRIVATE, 1] do
    {:direct, nil}
  end

  def resolve(%{chat_type: type, to: group_id} = message, _targets)
      when type in [:CHAT_GROUP, 2] and is_binary(group_id) do
    threshold = config(:downstream_group_large_threshold, 500)
    count = group_member_count(message, group_id)

    if count > threshold do
      {:group_aggregated, nil}
    else
      {:direct, nil}
    end
  end

  def resolve(%{chat_type: type}, _targets) when type in [:CHAT_ROOM, 3] do
    {config(:downstream_room_mode, :room_aggregated), nil}
  end

  def resolve(_message, _targets), do: {:direct, nil}

  defp group_member_count(message, group_id) do
    app_key = Map.get(message, :app_key) || Map.get(message, "app_key")

    cond do
      is_integer(Map.get(message, :member_count)) and Map.get(message, :member_count) > 0 ->
        message.member_count

      is_binary(app_key) ->
        case MetaCache.get(app_key, group_id) do
          {:ok, g} -> g.member_count || 0
          _ -> 0
        end

      true ->
        0
    end
  end

  defp config(key, default) do
    Application.get_env(:im, :event_bus_kafka, [])
    |> Keyword.get(key, default)
  end
end
