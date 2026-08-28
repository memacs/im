defmodule IM.Services.Room do
  @moduledoc "聊天室创建 / 加入 / 离开 / 解散 / 踢人 / 更新（P6 + P8-03）。"

  alias IM.Domain.{Error, MessageContext}
  alias IM.Room.{MemberCache, MetaCache}
  alias IM.Stores.RoomStore

  alias Pb.Im.Protocol.{
    RoomCreateReq,
    RoomCreateResp,
    RoomKickReq,
    RoomMemberPush,
    RoomOperatePush,
    RoomOperateReq,
    RoomUpdatePush,
    RoomUpdateReq
  }

  @doc """
  创建聊天室。
  """
  @spec create(RoomCreateReq.t(), MessageContext.t()) ::
          {:ok, RoomCreateResp.t()} | {:error, Error.t()}
  def create(%RoomCreateReq{} = req, %MessageContext{} = ctx) do
    name = req.name || ""

    if name == "" do
      {:error, Error.new(:msg_invalid, "name required")}
    else
      room_id =
        if req.room_id in [nil, ""],
          do: "r#{System.unique_integer([:positive])}",
          else: req.room_id

      attrs = %{
        app_key: ctx.app_key,
        room_id: room_id,
        name: name,
        owner_uid: ctx.user_id,
        max_members: if(req.max_members > 0, do: req.max_members, else: 10_000),
        persist_msg: req.persist_msg == true,
        msg_ttl_sec: if(req.msg_ttl_sec > 0, do: req.msg_ttl_sec, else: 300)
      }

      case RoomStore.create(attrs) do
        {:ok, room} ->
          :ok = MetaCache.put(room)
          :ok = MemberCache.put_member(room.app_key, room.room_id, ctx.user_id)

          {:ok,
           %RoomCreateResp{
             room_id: room.room_id,
             name: room.name,
             conv_id: "r:#{room.room_id}",
             created_at: DateTime.to_unix(room.inserted_at, :millisecond)
           }}

        {:error, _} = err ->
          err
      end
    end
  end

  @doc """
  加入聊天室（DB + 返回 PUSH 载荷）。调用方负责 PubSub.subscribe / broadcast。
  """
  @spec join(RoomOperateReq.t(), MessageContext.t()) ::
          {:ok, RoomMemberPush.t()} | {:error, Error.t()}
  def join(%RoomOperateReq{room_id: room_id}, %MessageContext{} = ctx)
      when room_id not in [nil, ""] do
    case RoomStore.join(ctx.app_key, room_id, ctx.user_id) do
      :ok ->
        :ok = MemberCache.put_member(ctx.app_key, room_id, ctx.user_id)
        {:ok, member_push(room_id, ctx.user_id, [ctx.user_id])}

      {:error, _} = err ->
        err
    end
  end

  def join(_, _), do: {:error, Error.new(:msg_invalid, "room_id required")}

  @doc """
  离开聊天室。
  """
  @spec leave(RoomOperateReq.t(), MessageContext.t()) ::
          {:ok, RoomMemberPush.t()} | {:error, Error.t()}
  def leave(%RoomOperateReq{room_id: room_id}, %MessageContext{} = ctx)
      when room_id not in [nil, ""] do
    :ok = RoomStore.leave(ctx.app_key, room_id, ctx.user_id)
    :ok = MemberCache.remove_member(ctx.app_key, room_id, ctx.user_id)
    {:ok, member_push(room_id, ctx.user_id, [ctx.user_id])}
  end

  def leave(_, _), do: {:error, Error.new(:msg_invalid, "room_id required")}

  @doc "解散（仅房主）。"
  @spec dismiss(RoomOperateReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def dismiss(%RoomOperateReq{} = req, %MessageContext{} = ctx) do
    with {:ok, room} <- fetch(ctx.app_key, req.room_id),
         :ok <- require_owner(room, ctx.user_id) do
      :ok = RoomStore.dismiss(ctx.app_key, room.room_id)
      :ok = MemberCache.invalidate(ctx.app_key, room.room_id)
      :ok = MetaCache.invalidate(ctx.app_key, room.room_id)

      push = %RoomOperatePush{
        room_id: room.room_id,
        conv_id: "r:#{room.room_id}",
        operator_uid: ctx.user_id,
        reason: req.reason || "",
        timestamp: System.system_time(:millisecond)
      }

      {:ok, %{push: push, push_cmd: :CMD_ROOM_DISMISS_PUSH, room_id: room.room_id}}
    end
  end

  @doc "踢人（仅房主）。"
  @spec kick(RoomKickReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def kick(%RoomKickReq{} = req, %MessageContext{} = ctx) do
    with {:ok, room} <- fetch(ctx.app_key, req.room_id),
         :ok <- require_owner(room, ctx.user_id) do
      targets =
        req.member_uids
        |> Enum.reject(&(&1 in [nil, "", ctx.user_id, room.owner_uid]))
        |> Enum.uniq()

      case RoomStore.remove_members(ctx.app_key, room.room_id, targets) do
        {:ok, removed} when removed != [] ->
          Enum.each(removed, &MemberCache.remove_member(ctx.app_key, room.room_id, &1))

          {:ok,
           %{
             push: member_push(room.room_id, ctx.user_id, removed),
             push_cmd: :CMD_ROOM_KICK_PUSH,
             room_id: room.room_id,
             kicked: removed
           }}

        {:ok, []} ->
          {:error, Error.new(:msg_invalid, "no members kicked")}

        {:error, :not_found} ->
          {:error, Error.new(:msg_invalid, "room not found")}
      end
    end
  end

  @doc "更新聊天室信息（仅房主）。"
  @spec update(RoomUpdateReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def update(%RoomUpdateReq{} = req, %MessageContext{} = ctx) do
    with {:ok, room} <- fetch(ctx.app_key, req.room_id),
         :ok <- require_owner(room, ctx.user_id) do
      attrs =
        %{}
        |> maybe_put(:name, req.name)
        |> maybe_put_int(:max_members, req.max_members)
        |> maybe_put_bool(:persist_msg, req)
        |> maybe_put_int(:msg_ttl_sec, req.msg_ttl_sec)

      case RoomStore.update_meta(ctx.app_key, room.room_id, attrs) do
        {:ok, r} ->
          :ok = MetaCache.put(r)

          push = %RoomUpdatePush{
            room_id: r.room_id,
            conv_id: "r:#{r.room_id}",
            operator_uid: ctx.user_id,
            name: r.name,
            timestamp: System.system_time(:millisecond)
          }

          {:ok, %{push: push, push_cmd: :CMD_ROOM_UPDATE_PUSH, room_id: r.room_id}}

        {:error, :not_found} ->
          {:error, Error.new(:msg_invalid, "room not found")}

        {:error, %Error{} = e} ->
          {:error, e}
      end
    end
  end

  defp member_push(room_id, operator, uids) do
    %RoomMemberPush{
      room_id: room_id,
      conv_id: "r:#{room_id}",
      operator_uid: operator,
      member_uids: uids,
      timestamp: System.system_time(:millisecond)
    }
  end

  defp fetch(_app, id) when id in [nil, ""],
    do: {:error, Error.new(:msg_invalid, "room_id required")}

  defp fetch(app_key, room_id) do
    case MetaCache.get(app_key, room_id) do
      {:ok, r} -> {:ok, r}
      {:error, :not_found} -> {:error, Error.new(:msg_invalid, "room not found")}
    end
  end

  defp require_owner(room, uid) do
    if room.owner_uid == uid do
      :ok
    else
      {:error, Error.new(:group_no_permission, "room owner required")}
    end
  end

  defp maybe_put(map, _k, v) when v in [nil, ""], do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp maybe_put_int(map, _k, n) when not is_integer(n) or n <= 0, do: map
  defp maybe_put_int(map, k, n), do: Map.put(map, k, n)

  defp maybe_put_bool(map, :persist_msg, %RoomUpdateReq{persist_msg: v}) when is_boolean(v),
    do: Map.put(map, :persist_msg, v)

  defp maybe_put_bool(map, _, _), do: map
end
