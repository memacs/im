defmodule IM.Services.Group do
  @moduledoc "群生命周期与管理（P8-01 / P8-02 / P8-04）。"

  alias IM.Domain.{Error, MessageContext}
  alias IM.Group.{MemberCache, MetaCache}
  alias IM.Group.FanoutPolicy
  alias IM.Schemas.Group
  alias IM.Stores.GroupStore

  alias Pb.Im.Protocol.{
    GroupAdminPush,
    GroupAdminReq,
    GroupCreateReq,
    GroupCreateResp,
    GroupKickReq,
    GroupInviteReq,
    GroupMemberPush,
    GroupOperatePush,
    GroupOperateReq,
    GroupTransferPush,
    GroupTransferReq,
    GroupUpdatePush,
    GroupUpdateReq
  }

  @doc """
  创建群。支持 map（REST）或 `GroupCreateReq`（WS）。

  ## 示例

      IM.Services.Group.create(%{"name" => "g", "member_uids" => ["u2"]}, ctx)
  """
  @spec create(map() | GroupCreateReq.t(), MessageContext.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def create(%GroupCreateReq{} = req, %MessageContext{} = ctx) do
    params = %{
      "name" => req.name,
      "group_id" => req.group_id,
      "member_uids" => req.member_uids,
      "announcement" => req.announcement,
      "max_members" => req.max_members
    }

    with {:ok, result} <- create(params, ctx) do
      ts = System.system_time(:millisecond)

      resp = %GroupCreateResp{
        group_id: result.group_id,
        name: result.name,
        conv_id: result.conv_id,
        created_at: ts
      }

      join_uids = List.wrap(result.initial_member_uids) -- [ctx.user_id]

      join_push =
        if join_uids == [] do
          nil
        else
          %GroupMemberPush{
            group_id: result.group_id,
            conv_id: result.conv_id,
            operator_uid: ctx.user_id,
            member_uids: join_uids,
            timestamp: ts
          }
        end

      {:ok,
       %{
         resp: resp,
         join_push: join_push,
         notify_user_ids: join_uids,
         exclude_device_id: ctx.device_id,
         # REST 兼容字段
         group_id: result.group_id,
         name: result.name,
         conv_id: result.conv_id,
         owner_uid: result.owner_uid,
         member_count: result.member_count,
         storage_mode: result.storage_mode
       }}
    end
  end

  def create(params, %MessageContext{} = ctx) when is_map(params) do
    name = str(params, "name")
    members = list_uids(params)

    if name == "" do
      {:error, Error.new(:msg_invalid, "name required")}
    else
      group_id =
        case str(params, "group_id") do
          "" -> "g#{System.unique_integer([:positive])}"
          id -> id
        end

      max_members =
        case Map.get(params, "max_members") || Map.get(params, :max_members) do
          n when is_integer(n) and n > 0 -> min(n, 10_000)
          _ -> 5000
        end

      attrs = %{
        app_key: ctx.app_key,
        group_id: group_id,
        name: name,
        owner_uid: ctx.user_id,
        announcement: str(params, "announcement"),
        max_members: max_members,
        persist_msg: true,
        storage_mode: "write_fanout"
      }

      case GroupStore.create(attrs, members) do
        {:ok, group} ->
          group = maybe_promote(group)
          :ok = MemberCache.warm(group.app_key, group.group_id)
          :ok = MetaCache.put(group)

          {:ok,
           %{
             group_id: group.group_id,
             name: group.name,
             conv_id: conv_id(group.group_id),
             owner_uid: group.owner_uid,
             member_count: group.member_count,
             storage_mode: group.storage_mode,
             initial_member_uids: members
           }}

        {:error, _} = err ->
          err
      end
    end
  end

  @doc "解散群（仅群主）。"
  @spec dismiss(GroupOperateReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def dismiss(%GroupOperateReq{} = req, %MessageContext{} = ctx) do
    with {:ok, group} <- fetch_group(ctx.app_key, req.group_id),
         :ok <- require_owner(ctx.app_key, group.group_id, ctx.user_id) do
      members = MemberCache.list_member_ids(ctx.app_key, group.group_id)
      :ok = GroupStore.dismiss(ctx.app_key, group.group_id)
      :ok = MemberCache.invalidate(ctx.app_key, group.group_id)
      :ok = MetaCache.invalidate(ctx.app_key, group.group_id)

      push = %GroupOperatePush{
        group_id: group.group_id,
        conv_id: conv_id(group.group_id),
        operator_uid: ctx.user_id,
        reason: req.reason || "",
        timestamp: System.system_time(:millisecond)
      }

      {:ok,
       %{
         push: push,
         notify_user_ids: members,
         exclude_device_id: ctx.device_id,
         push_cmd: :CMD_GROUP_DISMISS_PUSH
       }}
    end
  end

  @doc "主动入群。"
  @spec join(GroupOperateReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def join(%GroupOperateReq{} = req, %MessageContext{} = ctx) do
    with {:ok, group} <- fetch_group(ctx.app_key, req.group_id) do
      if MemberCache.member?(ctx.app_key, group.group_id, ctx.user_id) do
        {:error, Error.new(:group_already_member, "already member")}
      else
        case GroupStore.add_members(ctx.app_key, group.group_id, [ctx.user_id]) do
          {:ok, {added, g}} ->
            if ctx.user_id in added do
              g = maybe_promote(g)
              :ok = MemberCache.add_members(ctx.app_key, group.group_id, added)
              :ok = MetaCache.put(g)
              member_push_result(ctx, group.group_id, [ctx.user_id], :CMD_GROUP_JOIN_PUSH)
            else
              {:error, Error.new(:group_already_member, "already member")}
            end

          {:error, :member_limit} ->
            {:error, Error.new(:group_member_limit, "member limit")}

          {:error, %Error{} = e} ->
            {:error, e}

          {:error, :not_found} ->
            {:error, Error.new(:group_not_found, "group not found")}
        end
      end
    end
  end

  @doc "退群。"
  @spec leave(GroupOperateReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def leave(%GroupOperateReq{} = req, %MessageContext{} = ctx) do
    with {:ok, group} <- fetch_group(ctx.app_key, req.group_id),
         {:ok, m} <- fetch_member(ctx.app_key, group.group_id, ctx.user_id) do
      if m.role == GroupStore.role_owner() and group.member_count > 1 do
        {:error, Error.new(:group_no_permission, "owner must transfer before leave")}
      else
        members_before = MemberCache.list_member_ids(ctx.app_key, group.group_id)

        case GroupStore.remove_members(ctx.app_key, group.group_id, [ctx.user_id]) do
          {:ok, {removed, g}} ->
            :ok = MemberCache.remove_members(ctx.app_key, group.group_id, removed)
            :ok = MetaCache.put(g)

            if group.member_count <= 1 do
              _ = GroupStore.dismiss(ctx.app_key, group.group_id)
              :ok = MemberCache.invalidate(ctx.app_key, group.group_id)
              :ok = MetaCache.invalidate(ctx.app_key, group.group_id)
            end

            push = %GroupMemberPush{
              group_id: group.group_id,
              conv_id: conv_id(group.group_id),
              operator_uid: ctx.user_id,
              member_uids: [ctx.user_id],
              timestamp: System.system_time(:millisecond)
            }

            {:ok,
             %{
               push: push,
               notify_user_ids: members_before,
               exclude_device_id: ctx.device_id,
               push_cmd: :CMD_GROUP_LEAVE_PUSH
             }}

          {:error, :not_found} ->
            {:error, Error.new(:group_not_found, "group not found")}
        end
      end
    end
  end

  @doc "踢人。"
  @spec kick(GroupKickReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def kick(%GroupKickReq{} = req, %MessageContext{} = ctx) do
    with {:ok, group} <- fetch_group(ctx.app_key, req.group_id),
         {:ok, op} <- fetch_member(ctx.app_key, group.group_id, ctx.user_id),
         :ok <- require_admin_or_owner(op) do
      targets =
        req.member_uids
        |> Enum.reject(&(&1 in [nil, "", ctx.user_id, group.owner_uid]))
        |> Enum.uniq()

      with :ok <- validate_kick_targets(ctx.app_key, group.group_id, op, targets),
           {:ok, {removed, g}} <- GroupStore.remove_members(ctx.app_key, group.group_id, targets) do
        :ok = MemberCache.remove_members(ctx.app_key, group.group_id, removed)
        :ok = MetaCache.put(g)

        if removed == [] do
          {:error, Error.new(:msg_invalid, "no members kicked")}
        else
          members = MemberCache.list_member_ids(ctx.app_key, group.group_id) ++ removed

          push = %GroupMemberPush{
            group_id: group.group_id,
            conv_id: conv_id(group.group_id),
            operator_uid: ctx.user_id,
            member_uids: removed,
            timestamp: System.system_time(:millisecond)
          }

          {:ok,
           %{
             push: push,
             notify_user_ids: Enum.uniq(members),
             exclude_device_id: ctx.device_id,
             push_cmd: :CMD_GROUP_KICK_PUSH
           }}
        end
      else
        {:error, :not_found} -> {:error, Error.new(:group_not_found, "group not found")}
        {:error, %Error{} = e} -> {:error, e}
      end
    end
  end

  @doc "邀请入群。"
  @spec invite(GroupInviteReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def invite(%GroupInviteReq{} = req, %MessageContext{} = ctx) do
    with {:ok, group} <- fetch_group(ctx.app_key, req.group_id),
         {:ok, op} <- fetch_member(ctx.app_key, group.group_id, ctx.user_id),
         :ok <- require_admin_or_owner(op) do
      case GroupStore.add_members(ctx.app_key, group.group_id, req.member_uids) do
        {:ok, {added, g}} when added != [] ->
          g = maybe_promote(g)
          :ok = MemberCache.add_members(ctx.app_key, group.group_id, added)
          :ok = MetaCache.put(g)
          member_push_result(ctx, group.group_id, added, :CMD_GROUP_INVITE_PUSH)

        {:ok, {[], _}} ->
          {:error, Error.new(:group_already_member, "already members")}

        {:error, :member_limit} ->
          {:error, Error.new(:group_member_limit, "member limit")}

        {:error, :not_found} ->
          {:error, Error.new(:group_not_found, "group not found")}

        {:error, %Error{} = e} ->
          {:error, e}
      end
    end
  end

  @doc "设置管理员。"
  @spec set_admin(GroupAdminReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def set_admin(%GroupAdminReq{} = req, %MessageContext{} = ctx) do
    admin_role_change(req, ctx, GroupStore.role_admin(), :CMD_GROUP_SET_ADMIN_PUSH)
  end

  @doc "移除管理员。"
  @spec remove_admin(GroupAdminReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def remove_admin(%GroupAdminReq{} = req, %MessageContext{} = ctx) do
    admin_role_change(req, ctx, GroupStore.role_member(), :CMD_GROUP_REMOVE_ADMIN_PUSH)
  end

  @doc "转让群主。"
  @spec transfer(GroupTransferReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def transfer(%GroupTransferReq{} = req, %MessageContext{} = ctx) do
    with {:ok, group} <- fetch_group(ctx.app_key, req.group_id),
         :ok <- require_owner(ctx.app_key, group.group_id, ctx.user_id),
         {:ok, _} <- fetch_member(ctx.app_key, group.group_id, req.new_owner_uid) do
      if req.new_owner_uid == ctx.user_id do
        {:error, Error.new(:msg_invalid, "same owner")}
      else
        case GroupStore.transfer_owner(
               ctx.app_key,
               group.group_id,
               ctx.user_id,
               req.new_owner_uid
             ) do
          {:ok, g} ->
            :ok = MetaCache.put(g)

            push = %GroupTransferPush{
              group_id: group.group_id,
              conv_id: conv_id(group.group_id),
              old_owner_uid: ctx.user_id,
              new_owner_uid: req.new_owner_uid,
              timestamp: System.system_time(:millisecond)
            }

            {:ok,
             %{
               push: push,
               notify_user_ids: MemberCache.list_member_ids(ctx.app_key, group.group_id),
               exclude_device_id: ctx.device_id,
               push_cmd: :CMD_GROUP_TRANSFER_PUSH
             }}

          {:error, :not_found} ->
            {:error, Error.new(:group_not_found, "group not found")}
        end
      end
    end
  end

  @doc "更新群信息。"
  @spec update(GroupUpdateReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def update(%GroupUpdateReq{} = req, %MessageContext{} = ctx) do
    with {:ok, group} <- fetch_group(ctx.app_key, req.group_id),
         {:ok, op} <- fetch_member(ctx.app_key, group.group_id, ctx.user_id),
         :ok <- require_admin_or_owner(op) do
      attrs =
        %{}
        |> maybe_put(:name, req.name)
        |> maybe_put(:announcement, req.announcement)
        |> maybe_put_max(req.max_members)

      case GroupStore.update_meta(ctx.app_key, group.group_id, attrs) do
        {:ok, g} ->
          :ok = MetaCache.put(g)

          push = %GroupUpdatePush{
            group_id: g.group_id,
            conv_id: conv_id(g.group_id),
            operator_uid: ctx.user_id,
            name: g.name,
            announcement: g.announcement || "",
            timestamp: System.system_time(:millisecond)
          }

          {:ok,
           %{
             push: push,
             notify_user_ids: MemberCache.list_member_ids(ctx.app_key, g.group_id),
             exclude_device_id: ctx.device_id,
             push_cmd: :CMD_GROUP_UPDATE_PUSH
           }}

        {:error, :not_found} ->
          {:error, Error.new(:group_not_found, "group not found")}

        {:error, %Error{} = e} ->
          {:error, e}
      end
    end
  end

  @doc "禁言成员至 `muted_until_ms`（unix ms）；传 0 解除。"
  @spec mute_member(String.t(), String.t(), non_neg_integer(), MessageContext.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def mute_member(group_id, member_uid, muted_until_ms, %MessageContext{} = ctx)
      when is_binary(group_id) and is_binary(member_uid) and is_integer(muted_until_ms) do
    with {:ok, group} <- fetch_group(ctx.app_key, group_id),
         {:ok, op} <- fetch_member(ctx.app_key, group.group_id, ctx.user_id),
         :ok <- require_admin_or_owner(op),
         {:ok, _} <-
           GroupStore.set_muted_until(ctx.app_key, group.group_id, member_uid, muted_until_ms) do
      :ok = IM.Permission.MuteCache.put(ctx.app_key, group.group_id, member_uid, muted_until_ms)

      {:ok,
       %{
         group_id: group.group_id,
         member_uid: member_uid,
         muted_until: muted_until_ms
       }}
    end
  end

  defp admin_role_change(%GroupAdminReq{} = req, ctx, new_db_role, push_cmd) do
    with {:ok, group} <- fetch_group(ctx.app_key, req.group_id),
         :ok <- require_owner(ctx.app_key, group.group_id, ctx.user_id),
         {:ok, target} <- fetch_member(ctx.app_key, group.group_id, req.member_uid) do
      if target.role == GroupStore.role_owner() do
        {:error, Error.new(:group_no_permission, "cannot change owner role")}
      else
        case GroupStore.set_role(ctx.app_key, group.group_id, req.member_uid, new_db_role) do
          {:ok, _} ->
            push = %GroupAdminPush{
              group_id: group.group_id,
              conv_id: conv_id(group.group_id),
              operator_uid: ctx.user_id,
              member_uid: req.member_uid,
              new_role: proto_role(new_db_role),
              timestamp: System.system_time(:millisecond)
            }

            {:ok,
             %{
               push: push,
               notify_user_ids: MemberCache.list_member_ids(ctx.app_key, group.group_id),
               exclude_device_id: ctx.device_id,
               push_cmd: push_cmd
             }}

          {:error, :not_found} ->
            {:error, Error.new(:group_not_member, "not member")}
        end
      end
    end
  end

  defp member_push_result(ctx, group_id, member_uids, push_cmd) do
    members = MemberCache.list_member_ids(ctx.app_key, group_id)

    push = %GroupMemberPush{
      group_id: group_id,
      conv_id: conv_id(group_id),
      operator_uid: ctx.user_id,
      member_uids: member_uids,
      timestamp: System.system_time(:millisecond)
    }

    {:ok,
     %{
       push: push,
       notify_user_ids: members,
       exclude_device_id: ctx.device_id,
       push_cmd: push_cmd
     }}
  end

  defp validate_kick_targets(app_key, group_id, op, targets) do
    Enum.reduce_while(targets, :ok, fn uid, :ok ->
      case GroupStore.get_member(app_key, group_id, uid) do
        {:error, :not_found} ->
          {:halt, {:error, Error.new(:group_not_member, "not member: #{uid}")}}

        {:ok, t} ->
          cond do
            t.role == GroupStore.role_owner() ->
              {:halt, {:error, Error.new(:group_no_permission, "cannot kick owner")}}

            op.role == GroupStore.role_admin() and t.role != GroupStore.role_member() ->
              {:halt, {:error, Error.new(:group_no_permission, "admin can only kick members")}}

            true ->
              {:cont, :ok}
          end
      end
    end)
  end

  defp maybe_promote(%Group{} = group) do
    needs_promote? =
      FanoutPolicy.storage_mode(group) == :read_fanout and
        group.storage_mode not in ["read_fanout", :read_fanout]

    if needs_promote? do
      case GroupStore.promote_read_fanout(group) do
        {:ok, promoted} -> promoted
        _ -> group
      end
    else
      group
    end
  end

  defp fetch_group(_app_key, group_id) when group_id in [nil, ""] do
    {:error, Error.new(:msg_invalid, "group_id required")}
  end

  defp fetch_group(app_key, group_id) do
    case MetaCache.get(app_key, group_id) do
      {:ok, g} -> {:ok, g}
      {:error, :not_found} -> {:error, Error.new(:group_not_found, "group not found")}
    end
  end

  defp fetch_member(app_key, group_id, user_id) do
    case GroupStore.get_member(app_key, group_id, user_id) do
      {:ok, m} -> {:ok, m}
      {:error, :not_found} -> {:error, Error.new(:group_not_member, "not a member")}
    end
  end

  defp require_owner(app_key, group_id, user_id) do
    with {:ok, m} <- fetch_member(app_key, group_id, user_id) do
      if m.role == GroupStore.role_owner() do
        :ok
      else
        {:error, Error.new(:group_no_permission, "owner required")}
      end
    end
  end

  defp require_admin_or_owner(m) do
    if m.role >= GroupStore.role_admin() do
      :ok
    else
      {:error, Error.new(:group_no_permission, "admin or owner required")}
    end
  end

  defp proto_role(0), do: :GROUP_MEMBER_ROLE_MEMBER
  defp proto_role(1), do: :GROUP_MEMBER_ROLE_ADMIN
  defp proto_role(2), do: :GROUP_MEMBER_ROLE_OWNER

  defp conv_id(group_id), do: "g:#{group_id}"

  defp maybe_put(map, _k, v) when v in [nil, ""], do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp maybe_put_max(map, n) when is_integer(n) and n > 0,
    do: Map.put(map, :max_members, min(n, 10_000))

  defp maybe_put_max(map, _), do: map

  defp str(params, key, default \\ "") do
    atom =
      case key do
        "name" -> :name
        "group_id" -> :group_id
        "announcement" -> :announcement
        _ -> nil
      end

    case Map.get(params, key) || (atom && Map.get(params, atom)) do
      nil -> default
      v -> to_string(v)
    end
  end

  defp list_uids(params) do
    raw = Map.get(params, "member_uids") || Map.get(params, :member_uids) || []

    raw
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
  end
end
