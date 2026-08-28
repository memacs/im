defmodule IM.Permission.L1 do
  @moduledoc """
  权限热缓存 L1（进程内 ETS，短 TTL）。跨节点失效见 `IM.Permission.Invalidator`。
  """

  @table :im_permission_l1

  @doc "确保 ETS 表存在。"
  @spec ensure_table!() :: :ok
  def ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  @doc "清空（测试用）。"
  @spec reset!() :: :ok
  def reset! do
    ensure_table!()
    true = :ets.delete_all_objects(@table)
    :ok
  end

  @doc "读取；过期或不存在返回 `:miss`。"
  @spec get(term()) :: {:ok, boolean()} | :miss
  def get(key) do
    ensure_table!()
    now = System.system_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, {value, exp}}] when is_boolean(value) and is_integer(exp) and exp > now ->
        {:ok, value}

      [{^key, _}] ->
        true = :ets.delete(@table, key)
        :miss

      [] ->
        :miss
    end
  end

  @doc "写入并带 TTL。"
  @spec put(term(), boolean()) :: :ok
  def put(key, value) when is_boolean(value) do
    ensure_table!()
    ttl = Application.get_env(:im, :permission_l1_ttl_ms, 10_000)
    exp = System.system_time(:millisecond) + ttl
    true = :ets.insert(@table, {key, {value, exp}})
    :ok
  end

  @doc "按失效事件删除相关条目。"
  @spec invalidate(term()) :: :ok
  def invalidate({:block, app, blocker}) when is_binary(app) and is_binary(blocker) do
    ensure_table!()
    true = :ets.match_delete(@table, {{:block, app, blocker, :_}, :_})
    :ok
  end

  def invalidate({:mute, app, group_id}) when is_binary(app) and is_binary(group_id) do
    ensure_table!()
    true = :ets.match_delete(@table, {{:mute, app, group_id, :_}, :_})
    :ok
  end

  def invalidate({:device_ban, app, user_id, device_id})
      when is_binary(app) and is_binary(user_id) and is_binary(device_id) do
    ensure_table!()
    true = :ets.delete(@table, {:device_ban, app, user_id, device_id})
    :ok
  end

  def invalidate({:group_members, app, group_id}) when is_binary(app) and is_binary(group_id) do
    ensure_table!()
    true = :ets.match_delete(@table, {{:group_member, app, group_id, :_}, :_})
    :ok
  end

  def invalidate({:room_members, app, room_id}) when is_binary(app) and is_binary(room_id) do
    ensure_table!()
    true = :ets.match_delete(@table, {{:room_member, app, room_id, :_}, :_})
    :ok
  end

  def invalidate({:friendship, app, user_id, friend_id})
      when is_binary(app) and is_binary(user_id) and is_binary(friend_id) do
    ensure_table!()
    true = :ets.delete(@table, {:friendship, app, user_id, friend_id})
    :ok
  end

  def invalidate(_), do: :ok

  @doc "构造群成员 L1 key。"
  def group_member_key(app, group_id, user_id), do: {:group_member, app, group_id, user_id}

  @doc "构造聊天室成员 L1 key。"
  def room_member_key(app, room_id, user_id), do: {:room_member, app, room_id, user_id}

  @doc "构造好友关系 L1 key。"
  def friendship_key(app, user_id, friend_id), do: {:friendship, app, user_id, friend_id}

  @doc "构造拉黑 L1 key。"
  def block_key(app, blocker, blocked), do: {:block, app, blocker, blocked}

  @doc "构造禁言 L1 key。"
  def mute_key(app, group, user), do: {:mute, app, group, user}

  @doc "构造设备封禁 L1 key。"
  def device_ban_key(app, user, device), do: {:device_ban, app, user, device}
end
