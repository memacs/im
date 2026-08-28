defmodule IM.Stores.FriendStore do
  @moduledoc "friendships / friend_requests 持久化。"

  import Ecto.Query

  alias IM.Domain.Error
  alias IM.Repo
  alias IM.Schemas.{FriendRequest, Friendship}

  @doc "取单向好友关系。"
  @spec get_friendship(String.t(), String.t(), String.t()) ::
          {:ok, Friendship.t()} | {:error, :not_found}
  def get_friendship(app_key, user_id, friend_user_id) do
    case Repo.get_by(Friendship,
           app_key: app_key,
           user_id: user_id,
           friend_user_id: friend_user_id
         ) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  @doc "任一方拉黑则不可单聊。"
  @spec messaging_blocked?(String.t(), String.t(), String.t()) :: boolean()
  def messaging_blocked?(app_key, from_uid, to_uid) do
    from(f in Friendship,
      where:
        f.app_key == ^app_key and f.status == "blocked" and
          ((f.user_id == ^from_uid and f.friend_user_id == ^to_uid) or
             (f.user_id == ^to_uid and f.friend_user_id == ^from_uid)),
      select: 1,
      limit: 1
    )
    |> Repo.one()
    |> then(&(not is_nil(&1)))
  end

  @doc "upsert 好友关系行。"
  @spec upsert_friendship(map()) :: {:ok, Friendship.t()} | {:error, Error.t()}
  def upsert_friendship(attrs) when is_map(attrs) do
    app_key = attrs[:app_key] || attrs["app_key"]
    user_id = attrs[:user_id] || attrs["user_id"]
    friend = attrs[:friend_user_id] || attrs["friend_user_id"]

    case get_friendship(app_key, user_id, friend) do
      {:ok, row} ->
        row
        |> Friendship.changeset(attrs)
        |> Repo.update()
        |> cast_result()

      {:error, :not_found} ->
        %Friendship{}
        |> Friendship.changeset(attrs)
        |> Repo.insert()
        |> cast_result()
    end
  end

  @spec create_request(map()) :: {:ok, FriendRequest.t()} | {:error, Error.t()}
  def create_request(attrs) when is_map(attrs) do
    %FriendRequest{}
    |> FriendRequest.changeset(attrs)
    |> Repo.insert()
    |> cast_result()
  end

  @spec get_request(String.t(), String.t()) :: {:ok, FriendRequest.t()} | {:error, :not_found}
  def get_request(app_key, request_id) do
    case Repo.get_by(FriendRequest, app_key: app_key, request_id: request_id) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  @spec update_request(FriendRequest.t(), map()) ::
          {:ok, FriendRequest.t()} | {:error, Error.t()}
  def update_request(%FriendRequest{} = req, attrs) do
    req
    |> FriendRequest.changeset(attrs)
    |> Repo.update()
    |> cast_result()
  end

  @spec list_friends(String.t(), String.t(), pos_integer()) :: [Friendship.t()]
  def list_friends(app_key, user_id, limit \\ 100) do
    from(f in Friendship,
      where: f.app_key == ^app_key and f.user_id == ^user_id and f.status == "accepted",
      order_by: [asc: f.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "列出 `blocker` 拉黑的全部 user_id。"
  @spec list_blocked_user_ids(String.t(), String.t()) :: [String.t()]
  def list_blocked_user_ids(app_key, blocker_user_id) do
    from(f in Friendship,
      where: f.app_key == ^app_key and f.user_id == ^blocker_user_id and f.status == "blocked",
      select: f.friend_user_id
    )
    |> Repo.all()
  end

  @spec list_pending_requests(String.t(), String.t(), pos_integer()) :: [FriendRequest.t()]
  def list_pending_requests(app_key, to_user_id, limit \\ 50) do
    from(r in FriendRequest,
      where: r.app_key == ^app_key and r.to_user_id == ^to_user_id and r.status == "pending",
      order_by: [desc: r.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp cast_result({:ok, row}), do: {:ok, row}
  defp cast_result({:error, cs}), do: {:error, Error.new(:internal_error, inspect(cs.errors))}
end
