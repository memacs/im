defmodule IM.Stores.GroupStore do
  @moduledoc "groups / group_members 持久化。"

  import Ecto.Query

  alias IM.Domain.Error
  alias IM.Repo
  alias IM.Schemas.{Group, GroupMember}

  # DB：0=成员 1=管理 2=群主（与 proto 1/2/3 不同）
  @role_member 0
  @role_admin 1
  @role_owner 2

  @doc """
  按 group_id 取群。

  ## 示例

      IM.Stores.GroupStore.get("a", "g1")
  """
  @spec get(String.t(), String.t()) :: {:ok, Group.t()} | {:error, :not_found}
  def get(app_key, group_id) do
    case Repo.get_by(Group, app_key: app_key, group_id: group_id) do
      nil -> {:error, :not_found}
      group -> {:ok, group}
    end
  end

  @doc """
  取成员行。
  """
  @spec get_member(String.t(), String.t(), String.t()) ::
          {:ok, GroupMember.t()} | {:error, :not_found}
  def get_member(app_key, group_id, user_id) do
    case Repo.get_by(GroupMember, app_key: app_key, group_id: group_id, user_id: user_id) do
      nil -> {:error, :not_found}
      m -> {:ok, m}
    end
  end

  @doc "设置禁言截止时间（unix ms；0 表示解除）。"
  @spec set_muted_until(String.t(), String.t(), String.t(), non_neg_integer()) ::
          {:ok, GroupMember.t()} | {:error, Error.t()}
  def set_muted_until(app_key, group_id, user_id, muted_until)
      when is_integer(muted_until) and muted_until >= 0 do
    with {:ok, m} <- get_member(app_key, group_id, user_id) do
      m
      |> GroupMember.changeset(%{muted_until: muted_until})
      |> Repo.update()
      |> case do
        {:ok, row} -> {:ok, row}
        {:error, cs} -> {:error, Error.new(:internal_error, inspect(cs.errors))}
      end
    else
      {:error, :not_found} -> {:error, Error.new(:group_not_member, "not a group member")}
    end
  end

  @doc "成员当前是否处于禁言期。"
  @spec muted?(String.t(), String.t(), String.t(), non_neg_integer()) :: boolean()
  def muted?(app_key, group_id, user_id, now_ms \\ System.system_time(:millisecond)) do
    case get_member(app_key, group_id, user_id) do
      {:ok, %{muted_until: until}} when is_integer(until) and until > 0 -> until > now_ms
      _ -> false
    end
  end

  @doc "列出群内仍有效的禁言成员 `{user_id, muted_until}`。"
  @spec list_active_mutes(String.t(), String.t(), non_neg_integer()) :: [
          {String.t(), non_neg_integer()}
        ]
  def list_active_mutes(app_key, group_id, now_ms \\ System.system_time(:millisecond)) do
    from(m in GroupMember,
      where:
        m.app_key == ^app_key and m.group_id == ^group_id and m.muted_until > ^now_ms and
          m.muted_until > 0,
      select: {m.user_id, m.muted_until}
    )
    |> Repo.all()
  end

  @doc """
  列出群成员 user_id。

  ## 示例

      IM.Stores.GroupStore.list_member_ids("a", "g1")
  """
  @spec list_member_ids(String.t(), String.t()) :: [String.t()]
  def list_member_ids(app_key, group_id) do
    from(m in GroupMember,
      where: m.app_key == ^app_key and m.group_id == ^group_id,
      select: m.user_id
    )
    |> Repo.all()
  end

  @doc """
  是否为群成员。

  ## 示例

      IM.Stores.GroupStore.member?("a", "g1", "u1")
  """
  @spec member?(String.t(), String.t(), String.t()) :: boolean()
  def member?(app_key, group_id, user_id) do
    match?({:ok, _}, get_member(app_key, group_id, user_id))
  end

  @doc """
  晋升为读扩散并持久化（降员不回退）。
  """
  @spec promote_read_fanout(Group.t()) :: {:ok, Group.t()} | {:error, Error.t()}
  def promote_read_fanout(%Group{} = group) do
    group
    |> Group.changeset(%{storage_mode: "read_fanout"})
    |> Repo.update()
    |> case do
      {:ok, g} -> {:ok, g}
      {:error, cs} -> {:error, Error.new(:internal_error, inspect(cs.errors))}
    end
  end

  @doc """
  建群并写入成员（owner role=2）。

  ## 示例

      IM.Stores.GroupStore.create(%{app_key: "a", group_id: "g1", ...}, ["u1", "u2"])
  """
  @spec create(map(), [String.t()]) :: {:ok, Group.t()} | {:error, Error.t()}
  def create(attrs, member_uids) when is_list(member_uids) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    owner = attrs[:owner_uid] || attrs["owner_uid"]
    members = [owner | member_uids] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()

    attrs =
      attrs
      |> Map.new()
      |> Map.put(:member_count, length(members))
      |> Map.put_new(:storage_mode, "write_fanout")

    Repo.transaction(fn ->
      group =
        %Group{}
        |> Group.changeset(attrs)
        |> Repo.insert!()

      Enum.each(members, fn uid ->
        role = if uid == owner, do: @role_owner, else: @role_member

        %GroupMember{}
        |> GroupMember.changeset(%{
          app_key: group.app_key,
          group_id: group.group_id,
          user_id: uid,
          role: role,
          muted_until: 0,
          joined_at: now
        })
        |> Repo.insert!()
      end)

      group
    end)
    |> case do
      {:ok, group} -> {:ok, group}
      {:error, reason} -> {:error, Error.new(:internal_error, inspect(reason))}
    end
  end

  @doc """
  解散：删除成员与群行。
  """
  @spec dismiss(String.t(), String.t()) :: :ok | {:error, :not_found}
  def dismiss(app_key, group_id) do
    case get(app_key, group_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, group} ->
        Repo.transaction(fn ->
          from(m in GroupMember, where: m.app_key == ^app_key and m.group_id == ^group_id)
          |> Repo.delete_all()

          Repo.delete!(group)
        end)

        :ok
    end
  end

  @doc """
  添加成员（已存在则跳过）。返回实际新增的 uid 列表。
  """
  @spec add_members(String.t(), String.t(), [String.t()]) ::
          {:ok, {[String.t()], Group.t()}} | {:error, Error.t() | :not_found | :member_limit}
  def add_members(app_key, group_id, uids) when is_list(uids) do
    with {:ok, group} <- get(app_key, group_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      candidates = uids |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()

      existing =
        from(m in GroupMember,
          where: m.app_key == ^app_key and m.group_id == ^group_id and m.user_id in ^candidates,
          select: m.user_id
        )
        |> Repo.all()
        |> MapSet.new()

      to_add = Enum.reject(candidates, &MapSet.member?(existing, &1))

      if group.member_count + length(to_add) > group.max_members do
        {:error, :member_limit}
      else
        Repo.transaction(fn ->
          Enum.each(to_add, fn uid ->
            %GroupMember{}
            |> GroupMember.changeset(%{
              app_key: app_key,
              group_id: group_id,
              user_id: uid,
              role: @role_member,
              muted_until: 0,
              joined_at: now
            })
            |> Repo.insert!()
          end)

          group =
            group
            |> Group.changeset(%{member_count: group.member_count + length(to_add)})
            |> Repo.update!()

          {to_add, group}
        end)
        |> case do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, Error.new(:internal_error, inspect(reason))}
        end
      end
    end
  end

  @doc """
  移除成员。返回实际移除的 uid 列表。
  """
  @spec remove_members(String.t(), String.t(), [String.t()]) ::
          {:ok, {[String.t()], Group.t()}} | {:error, :not_found}
  def remove_members(app_key, group_id, uids) when is_list(uids) do
    with {:ok, group} <- get(app_key, group_id) do
      targets = uids |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()

      {n, _} =
        from(m in GroupMember,
          where: m.app_key == ^app_key and m.group_id == ^group_id and m.user_id in ^targets
        )
        |> Repo.delete_all()

      if n == 0 do
        {:ok, {[], group}}
      else
        group
        |> Group.changeset(%{member_count: max(group.member_count - n, 0)})
        |> Repo.update()
        |> case do
          {:ok, g} -> {:ok, {targets, g}}
          _ -> {:error, :not_found}
        end
      end
    end
  end

  @doc """
  设置成员角色（DB 值）。
  """
  @spec set_role(String.t(), String.t(), String.t(), non_neg_integer()) ::
          {:ok, GroupMember.t()} | {:error, :not_found}
  def set_role(app_key, group_id, user_id, role)
      when role in [@role_member, @role_admin, @role_owner] do
    with {:ok, m} <- get_member(app_key, group_id, user_id) do
      m
      |> GroupMember.changeset(%{role: role})
      |> Repo.update()
      |> case do
        {:ok, updated} -> {:ok, updated}
        _ -> {:error, :not_found}
      end
    end
  end

  @doc """
  转让群主：旧主降为成员，新主升为 owner，并更新 groups.owner_uid。
  """
  @spec transfer_owner(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Group.t()} | {:error, :not_found}
  def transfer_owner(app_key, group_id, old_owner, new_owner) do
    with {:ok, group} <- get(app_key, group_id),
         {:ok, _} <- get_member(app_key, group_id, new_owner) do
      Repo.transaction(fn ->
        {:ok, _} = set_role(app_key, group_id, old_owner, @role_member)
        {:ok, _} = set_role(app_key, group_id, new_owner, @role_owner)

        group
        |> Group.changeset(%{owner_uid: new_owner})
        |> Repo.update!()
      end)
      |> case do
        {:ok, g} -> {:ok, g}
        {:error, _} -> {:error, :not_found}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  更新群元数据。
  """
  @spec update_meta(String.t(), String.t(), map()) ::
          {:ok, Group.t()} | {:error, :not_found | Error.t()}
  def update_meta(app_key, group_id, attrs) when is_map(attrs) do
    with {:ok, group} <- get(app_key, group_id) do
      group
      |> Group.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, g} -> {:ok, g}
        {:error, cs} -> {:error, Error.new(:msg_invalid, inspect(cs.errors))}
      end
    end
  end

  def role_member, do: @role_member
  def role_admin, do: @role_admin
  def role_owner, do: @role_owner
end
