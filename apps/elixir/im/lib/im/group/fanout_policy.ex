defmodule IM.Group.FanoutPolicy do
  @moduledoc """
  写扩散 / 读扩散 / 是否走树状推送的统一判定。

  禁止在 Handler / Store 内散落 threshold 判断。
  """

  alias IM.Group.FanoutConfig
  alias IM.Schemas.Group

  @type storage_mode :: :write_fanout | :read_fanout

  @doc """
  群消息持久化模式。

  ## 示例

      :write_fanout = IM.Group.FanoutPolicy.storage_mode(group)
  """
  @spec storage_mode(Group.t() | map()) :: storage_mode()
  def storage_mode(%{storage_mode_override: "write_fanout"}), do: :write_fanout
  def storage_mode(%{storage_mode_override: "read_fanout"}), do: :read_fanout
  def storage_mode(%{storage_mode_override: :write_fanout}), do: :write_fanout
  def storage_mode(%{storage_mode_override: :read_fanout}), do: :read_fanout

  def storage_mode(%{storage_mode: "read_fanout"}), do: :read_fanout
  def storage_mode(%{storage_mode: :read_fanout}), do: :read_fanout

  def storage_mode(group) do
    cond do
      System.get_env("IM_GROUP_READ_FANOUT_ENABLED") == "false" ->
        :write_fanout

      FanoutConfig.get(:read_fanout_enabled) == false ->
        :write_fanout

      Map.get(group, :storage_mode) in ["read_fanout", :read_fanout] ->
        :read_fanout

      true ->
        count = Map.get(group, :member_count) || 0
        threshold = FanoutConfig.get(:read_fanout_threshold)
        if count > threshold, do: :read_fanout, else: :write_fanout
    end
  end

  @doc """
  在线规模是否走树状扇出。

  ## 示例

      IM.Group.FanoutPolicy.use_tree_push?(600)
  """
  @spec use_tree_push?(non_neg_integer()) :: boolean()
  def use_tree_push?(online_or_recipient_count)
      when is_integer(online_or_recipient_count) and online_or_recipient_count >= 0 do
    online_or_recipient_count > FanoutConfig.get(:tree_threshold)
  end

  @doc """
  扩员后若需晋升读扩散则写回 `storage_mode`（非发消息热路径）。
  """
  @spec maybe_promote_mode(Group.t()) :: storage_mode()
  def maybe_promote_mode(%Group{} = group) do
    case storage_mode(group) do
      :read_fanout -> :read_fanout
      other -> other
    end
  end
end
