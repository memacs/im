defmodule IM.Services.Friend do
  @moduledoc "好友关系与拉黑（P8-05 ~ P8-09）。"

  alias IM.Domain.{Error, MessageContext}
  alias IM.Permission.BlockCache
  alias IM.Friend.FriendshipCache
  alias IM.Stores.{AppConfigStore, FriendStore}
  alias Pb.Im.Protocol.{
    FriendAcceptNotify,
    FriendAcceptReq,
    FriendAcceptResp,
    FriendAddReq,
    FriendAddResp,
    FriendBlockNotify,
    FriendBlockReq,
    FriendBlockResp,
    FriendDeleteNotify,
    FriendDeleteReq,
    FriendDeleteResp,
    FriendInfo,
    FriendListReq,
    FriendListResp,
    FriendRejectNotify,
    FriendRejectReq,
    FriendRejectResp,
    FriendRequestInfo,
    FriendRequestListReq,
    FriendRequestListResp,
    FriendRequestNotify,
    FriendSetRemarkReq,
    FriendSetRemarkResp,
    FriendUnblockReq,
    FriendUnblockResp
  }

  @request_ttl_sec 7 * 24 * 3600

  @doc """
  单聊发消息权限：拉黑优先，其次租户「须为好友才能单聊」。

  ## 示例

      IM.Services.Friend.check_send_permission(app_key, from, to)
  """
  @spec check_send_permission(String.t(), String.t(), String.t()) ::
          :ok | {:error, Error.t()}
  def check_send_permission(app_key, from_user_id, to_user_id)
      when is_binary(app_key) and is_binary(from_user_id) and is_binary(to_user_id) do
    cond do
      BlockCache.blocked?(app_key, from_user_id, to_user_id) ->
        {:error, Error.new(:friend_blocked, "you blocked peer")}

      BlockCache.blocked?(app_key, to_user_id, from_user_id) ->
        {:error, Error.new(:friend_blocked_by_peer, "blocked by peer")}

      require_friend_to_send?(app_key) and not friends?(app_key, from_user_id, to_user_id) ->
        {:error, Error.new(:friend_not_friend, "friendship required")}

      true ->
        :ok
    end
  end

  @doc "双方是否为 accepted 好友。"
  @spec friends?(String.t(), String.t(), String.t()) :: boolean()
  def friends?(app_key, user_a, user_b) do
    FriendshipCache.friends?(app_key, user_a, user_b)
  end

  @doc "租户是否开启须好友才能单聊（默认 false）。"
  @spec require_friend_to_send?(String.t()) :: boolean()
  def require_friend_to_send?(app_key) when is_binary(app_key) do
    env_default = Application.get_env(:im, :require_friend_to_send, false)

    AppConfigStore.get_boolean(app_key, "friend", "require_friend_to_send", env_default)
  end

  @doc "发起好友请求。"
  @spec add(FriendAddReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def add(%FriendAddReq{} = req, %MessageContext{} = ctx) do
    to = req.to_user_id || ""

    cond do
      to == "" ->
        {:error, Error.new(:msg_invalid, "to_user_id required")}

      to == ctx.user_id ->
        {:error, Error.new(:friend_self, "cannot add self")}

      FriendStore.messaging_blocked?(ctx.app_key, ctx.user_id, to) ->
        {:error, Error.new(:friend_blocked, "blocked")}

      true ->
        case FriendStore.get_friendship(ctx.app_key, ctx.user_id, to) do
          {:ok, %{status: "accepted"}} ->
            {:error, Error.new(:friend_already, "already friends")}

          _ ->
            request_id = "fr#{System.unique_integer([:positive])}"
            now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
            expires = DateTime.add(now, @request_ttl_sec, :second)

            with {:ok, fr} <-
                   FriendStore.create_request(%{
                     app_key: ctx.app_key,
                     request_id: request_id,
                     from_user_id: ctx.user_id,
                     to_user_id: to,
                     message: req.message || "",
                     status: "pending",
                     expires_at: expires
                   }),
                 {:ok, _} <-
                   FriendStore.upsert_friendship(%{
                     app_key: ctx.app_key,
                     user_id: ctx.user_id,
                     friend_user_id: to,
                     status: "pending",
                     remark: blank_to_nil(req.remark)
                   }) do
              resp = %FriendAddResp{
                request_id: fr.request_id,
                status: :FRIEND_STATUS_PENDING
              }

              notify = %FriendRequestNotify{
                request_id: fr.request_id,
                from_user_id: ctx.user_id,
                message: fr.message || "",
                timestamp: DateTime.to_unix(fr.inserted_at, :millisecond)
              }

              {:ok,
               %{
                 resp: resp,
                 notify: notify,
                 notify_user_id: to,
                 resp_cmd: :CMD_FRIEND_ADD_RESP,
                 push_cmd: :CMD_FRIEND_REQUEST_PUSH
               }}
            end
        end
    end
  end

  @doc "接受好友请求。"
  @spec accept(FriendAcceptReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def accept(%FriendAcceptReq{} = req, %MessageContext{} = ctx) do
    with {:ok, fr} <- fetch_pending(ctx.app_key, req.request_id, ctx.user_id) do
      from = fr.from_user_id

      with {:ok, _} <- FriendStore.update_request(fr, %{status: "accepted"}),
           {:ok, _} <-
             FriendStore.upsert_friendship(%{
               app_key: ctx.app_key,
               user_id: ctx.user_id,
               friend_user_id: from,
               status: "accepted",
               remark: blank_to_nil(req.remark)
             }),
           {:ok, _} <-
             FriendStore.upsert_friendship(%{
               app_key: ctx.app_key,
               user_id: from,
               friend_user_id: ctx.user_id,
               status: "accepted"
             }) do
        :ok = FriendshipCache.put_accepted(ctx.app_key, ctx.user_id, from)
        :ok = FriendshipCache.put_accepted(ctx.app_key, from, ctx.user_id)

        resp = %FriendAcceptResp{friend_user_id: from, status: :FRIEND_STATUS_ACCEPTED}

        notify = %FriendAcceptNotify{
          user_id: ctx.user_id,
          timestamp: System.system_time(:millisecond)
        }

        {:ok,
         %{
           resp: resp,
           notify: notify,
           notify_user_id: from,
           resp_cmd: :CMD_FRIEND_ACCEPT_RESP,
           push_cmd: :CMD_FRIEND_ACCEPT_PUSH
         }}
      end
    end
  end

  @doc "拒绝好友请求。"
  @spec reject(FriendRejectReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def reject(%FriendRejectReq{} = req, %MessageContext{} = ctx) do
    with {:ok, fr} <- fetch_pending(ctx.app_key, req.request_id, ctx.user_id),
         {:ok, _} <- FriendStore.update_request(fr, %{status: "rejected"}) do
      _ =
        FriendStore.upsert_friendship(%{
          app_key: ctx.app_key,
          user_id: fr.from_user_id,
          friend_user_id: ctx.user_id,
          status: "deleted"
        })

      resp = %FriendRejectResp{friend_user_id: fr.from_user_id}

      notify = %FriendRejectNotify{
        user_id: ctx.user_id,
        timestamp: System.system_time(:millisecond)
      }

      {:ok,
       %{
         resp: resp,
         notify: notify,
         notify_user_id: fr.from_user_id,
         resp_cmd: :CMD_FRIEND_REJECT_RESP,
         push_cmd: :CMD_FRIEND_REJECT_PUSH
       }}
    end
  end

  @doc "删除好友（双向）。"
  @spec delete(FriendDeleteReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def delete(%FriendDeleteReq{} = req, %MessageContext{} = ctx) do
    peer = req.friend_user_id || ""

    if peer == "" do
      {:error, Error.new(:msg_invalid, "friend_user_id required")}
    else
      with {:ok, _} <-
             FriendStore.upsert_friendship(%{
               app_key: ctx.app_key,
               user_id: ctx.user_id,
               friend_user_id: peer,
               status: "deleted"
             }),
           {:ok, _} <-
             FriendStore.upsert_friendship(%{
               app_key: ctx.app_key,
               user_id: peer,
               friend_user_id: ctx.user_id,
               status: "deleted"
             }) do
        :ok = FriendshipCache.put_not_friend(ctx.app_key, ctx.user_id, peer)
        :ok = FriendshipCache.put_not_friend(ctx.app_key, peer, ctx.user_id)

        resp = %FriendDeleteResp{friend_user_id: peer}

        notify = %FriendDeleteNotify{
          user_id: ctx.user_id,
          timestamp: System.system_time(:millisecond)
        }

        {:ok,
         %{
           resp: resp,
           notify: notify,
           notify_user_id: peer,
           resp_cmd: :CMD_FRIEND_DELETE_RESP,
           push_cmd: :CMD_FRIEND_DELETE_PUSH
         }}
      end
    end
  end

  @doc "拉黑。"
  @spec block(FriendBlockReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def block(%FriendBlockReq{} = req, %MessageContext{} = ctx) do
    peer = req.user_id || ""

    cond do
      peer == "" ->
        {:error, Error.new(:msg_invalid, "user_id required")}

      peer == ctx.user_id ->
        {:error, Error.new(:friend_self, "cannot block self")}

      true ->
        with {:ok, _} <-
               FriendStore.upsert_friendship(%{
                 app_key: ctx.app_key,
                 user_id: ctx.user_id,
                 friend_user_id: peer,
                 status: "blocked"
               }) do
          :ok = BlockCache.put(ctx.app_key, ctx.user_id, peer)
          resp = %FriendBlockResp{user_id: peer}

          notify = %FriendBlockNotify{
            user_id: ctx.user_id,
            timestamp: System.system_time(:millisecond)
          }

          {:ok,
           %{
             resp: resp,
             notify: notify,
             notify_user_id: peer,
             resp_cmd: :CMD_FRIEND_BLOCK_RESP,
             push_cmd: :CMD_FRIEND_BLOCK_PUSH
           }}
        end
    end
  end

  @doc "取消拉黑。"
  @spec unblock(FriendUnblockReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def unblock(%FriendUnblockReq{} = req, %MessageContext{} = ctx) do
    peer = req.user_id || ""

    with {:ok, row} <- FriendStore.get_friendship(ctx.app_key, ctx.user_id, peer) do
      if row.status != "blocked" do
        {:error, Error.new(:friend_no_permission, "not blocked")}
      else
        with {:ok, _} <-
               FriendStore.upsert_friendship(%{
                 app_key: ctx.app_key,
                 user_id: ctx.user_id,
                 friend_user_id: peer,
                 status: "deleted"
               }) do
          :ok = BlockCache.delete(ctx.app_key, ctx.user_id, peer)

          {:ok,
           %{
             resp: %FriendUnblockResp{user_id: peer},
             resp_cmd: :CMD_FRIEND_UNBLOCK_RESP,
             notify: nil,
             notify_user_id: nil,
             push_cmd: nil
           }}
        end
      end
    else
      {:error, :not_found} -> {:error, Error.new(:friend_not_friend, "not found")}
    end
  end

  @doc "设置备注。"
  @spec set_remark(FriendSetRemarkReq.t(), MessageContext.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def set_remark(%FriendSetRemarkReq{} = req, %MessageContext{} = ctx) do
    with {:ok, row} <- FriendStore.get_friendship(ctx.app_key, ctx.user_id, req.friend_user_id) do
      if row.status != "accepted" do
        {:error, Error.new(:friend_not_friend, "not friends")}
      else
        with {:ok, updated} <-
               FriendStore.upsert_friendship(%{
                 app_key: ctx.app_key,
                 user_id: ctx.user_id,
                 friend_user_id: req.friend_user_id,
                 status: "accepted",
                 remark: req.remark || ""
               }) do
          {:ok,
           %{
             resp: %FriendSetRemarkResp{
               friend_user_id: updated.friend_user_id,
               remark: updated.remark || ""
             },
             resp_cmd: :CMD_FRIEND_SET_REMARK_RESP,
             notify: nil,
             notify_user_id: nil,
             push_cmd: nil
           }}
        end
      end
    else
      {:error, :not_found} -> {:error, Error.new(:friend_not_friend, "not friends")}
    end
  end

  @doc "好友列表。"
  @spec list(FriendListReq.t(), MessageContext.t()) :: {:ok, map()} | {:error, Error.t()}
  def list(%FriendListReq{} = req, %MessageContext{} = ctx) do
    limit = clamp(req.limit, 100, 500)
    rows = FriendStore.list_friends(ctx.app_key, ctx.user_id, limit)

    friends =
      Enum.map(rows, fn f ->
        %FriendInfo{
          user_id: f.friend_user_id,
          remark: f.remark || "",
          status: :FRIEND_STATUS_ACCEPTED,
          created_at: DateTime.to_unix(f.inserted_at, :millisecond)
        }
      end)

    {:ok,
     %{
       resp: %FriendListResp{friends: friends, next_cursor: "", has_more: false},
       resp_cmd: :CMD_FRIEND_LIST_RESP,
       notify: nil,
       notify_user_id: nil,
       push_cmd: nil
     }}
  end

  @doc "好友请求列表（收件箱）。"
  @spec request_list(FriendRequestListReq.t(), MessageContext.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def request_list(%FriendRequestListReq{} = req, %MessageContext{} = ctx) do
    limit = clamp(req.limit, 50, 200)
    rows = FriendStore.list_pending_requests(ctx.app_key, ctx.user_id, limit)

    requests =
      Enum.map(rows, fn r ->
        %FriendRequestInfo{
          request_id: r.request_id,
          from_user_id: r.from_user_id,
          to_user_id: r.to_user_id,
          message: r.message || "",
          status: :FRIEND_REQUEST_STATUS_PENDING,
          timestamp: DateTime.to_unix(r.inserted_at, :millisecond)
        }
      end)

    {:ok,
     %{
       resp: %FriendRequestListResp{requests: requests, next_cursor: "", has_more: false},
       resp_cmd: :CMD_FRIEND_REQUEST_LIST_RESP,
       notify: nil,
       notify_user_id: nil,
       push_cmd: nil
     }}
  end

  defp fetch_pending(app_key, request_id, to_uid) do
    case FriendStore.get_request(app_key, request_id) do
      {:ok, %{status: "pending", to_user_id: ^to_uid} = fr} ->
        {:ok, fr}

      {:ok, _} ->
        {:error, Error.new(:friend_no_permission, "not your request")}

      {:error, :not_found} ->
        {:error, Error.new(:friend_request_not_found, "request not found")}
    end
  end

  defp blank_to_nil(v) when v in [nil, ""], do: nil
  defp blank_to_nil(v), do: v

  defp clamp(n, default, _max) when not is_integer(n) or n <= 0, do: default
  defp clamp(n, _default, max), do: min(n, max)
end
