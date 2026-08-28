defmodule IM.Permission.Reconciler do
  @moduledoc """
  权限热缓存对账：抽样比对 PG 与 L2，修复漂移（DD-033 §5）。
  """

  import Ecto.Query

  alias IM.Cache
  alias IM.Friend.FriendshipCache
  alias IM.Group.MemberCache
  alias IM.Permission.Telemetry
  alias IM.Repo
  alias IM.Schemas.{Friendship, GroupMember, UserDevice}
  alias IM.Stores.GroupStore

  @doc """
  对指定 `app_key` 抽样对账。

  ## Options

  - `:sample` — 每类抽样上限（默认 200）
  """
  @spec run(String.t(), keyword()) :: map()
  def run(app_key, opts \\ []) when is_binary(app_key) do
    sample = Keyword.get(opts, :sample, 200)

    block = reconcile_blocks(app_key, sample)
    mute = reconcile_mutes(app_key, sample)
    device = reconcile_device_bans(app_key, sample)
    group_member = reconcile_group_members(app_key, sample)
    friendship = reconcile_friendships(app_key, sample)

    Telemetry.emit_drift(:block, block)
    Telemetry.emit_drift(:mute, mute)
    Telemetry.emit_drift(:device_ban, device)
    Telemetry.emit_drift(:group_member, group_member)
    Telemetry.emit_drift(:friendship, friendship)

    %{
      block: block,
      mute: mute,
      device_ban: device,
      group_member: group_member,
      friendship: friendship
    }
  end

  defp reconcile_blocks(app_key, sample) do
    rows =
      from(f in Friendship,
        where: f.app_key == ^app_key and f.status == "blocked",
        order_by: [desc: f.id],
        limit: ^sample,
        select: {f.user_id, f.friend_user_id}
      )
      |> Repo.all()

    Enum.reduce(rows, 0, fn {blocker, blocked}, acc ->
      key = "im:block:#{app_key}:#{blocker}"

      case Cache.sismember(key, blocked) do
        {:ok, true} ->
          acc

        {:ok, false} ->
          _ = Cache.sadd(key, blocked)
          _ = Cache.set("im:block:#{app_key}:#{blocker}:loaded", "1")
          acc + 1

        {:error, _} ->
          acc
      end
    end)
  end

  defp reconcile_mutes(app_key, sample) do
    now = System.system_time(:millisecond)

    rows =
      from(m in GroupMember,
        where: m.app_key == ^app_key and m.muted_until > ^now and m.muted_until > 0,
        order_by: [desc: m.id],
        limit: ^sample,
        select: {m.group_id, m.user_id, m.muted_until}
      )
      |> Repo.all()

    Enum.reduce(rows, 0, fn {group_id, user_id, until}, acc ->
      key = "im:mute:#{app_key}:#{group_id}"

      case Cache.zscore(key, user_id) do
        {:ok, score} when is_number(score) and trunc(score) == until ->
          acc

        {:ok, _} ->
          _ = Cache.zadd(key, user_id, until)
          _ = Cache.set("im:mute:#{app_key}:#{group_id}:loaded", "1")
          acc + 1

        {:error, _} ->
          acc
      end
    end)
  end

  defp reconcile_device_bans(app_key, sample) do
    rows =
      from(d in UserDevice,
        where: d.app_key == ^app_key and not is_nil(d.banned_at),
        order_by: [desc: d.id],
        limit: ^sample,
        select: {d.user_id, d.device_id}
      )
      |> Repo.all()

    Enum.reduce(rows, 0, fn {user_id, device_id}, acc ->
      key = "im:device_ban:#{app_key}:#{user_id}:#{device_id}"

      case Cache.get(key) do
        {:ok, "1"} ->
          acc

        {:ok, _} ->
          _ = Cache.set(key, "1")
          acc + 1

        {:error, _} ->
          acc
      end
    end)
  end

  defp reconcile_group_members(app_key, sample) do
    group_ids =
      from(m in GroupMember,
        where: m.app_key == ^app_key,
        distinct: m.group_id,
        order_by: [desc: m.group_id],
        limit: ^sample,
        select: m.group_id
      )
      |> Repo.all()

    Enum.reduce(group_ids, 0, fn group_id, acc ->
      pg_set = GroupStore.list_member_ids(app_key, group_id) |> MapSet.new()

      cache_set =
        case Cache.smembers("im:group:members:#{app_key}:#{group_id}") do
          {:ok, ids} -> MapSet.new(ids)
          {:error, _} -> MapSet.new()
        end

      if MapSet.equal?(pg_set, cache_set) or MapSet.size(pg_set) == 0 do
        acc
      else
        :ok = MemberCache.invalidate(app_key, group_id)
        :ok = MemberCache.warm(app_key, group_id)
        acc + 1
      end
    end)
  end

  defp reconcile_friendships(app_key, sample) do
    rows =
      from(f in Friendship,
        where: f.app_key == ^app_key and f.status == "accepted",
        order_by: [desc: f.id],
        limit: ^sample,
        select: {f.user_id, f.friend_user_id}
      )
      |> Repo.all()

    Enum.reduce(rows, 0, fn {user_id, friend_user_id}, acc ->
      key = "im:friend:#{app_key}:#{user_id}:#{friend_user_id}"

      case Cache.get(key) do
        {:ok, "1"} ->
          acc

        _ ->
          :ok = FriendshipCache.put_accepted(app_key, user_id, friend_user_id)
          acc + 1
      end
    end)
  end
end
