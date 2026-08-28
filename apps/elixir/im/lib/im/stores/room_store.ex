defmodule IM.Stores.RoomStore do
  @moduledoc "rooms / room_members 持久化。"

  import Ecto.Query

  alias IM.Domain.Error
  alias IM.Repo
  alias IM.Schemas.{Room, RoomMember}

  @spec get(String.t(), String.t()) :: {:ok, Room.t()} | {:error, :not_found}
  def get(app_key, room_id) do
    case Repo.get_by(Room, app_key: app_key, room_id: room_id) do
      nil -> {:error, :not_found}
      room -> {:ok, room}
    end
  end

  @spec member?(String.t(), String.t(), String.t()) :: boolean()
  def member?(app_key, room_id, user_id) do
    from(m in RoomMember,
      where: m.app_key == ^app_key and m.room_id == ^room_id and m.user_id == ^user_id,
      select: 1,
      limit: 1
    )
    |> Repo.one()
    |> then(&(not is_nil(&1)))
  end

  @spec create(map()) :: {:ok, Room.t()} | {:error, Error.t()}
  def create(attrs) when is_map(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.transaction(fn ->
      room =
        %Room{}
        |> Room.changeset(Map.put(attrs, :member_count, 1))
        |> Repo.insert!()

      %RoomMember{}
      |> RoomMember.changeset(%{
        app_key: room.app_key,
        room_id: room.room_id,
        user_id: room.owner_uid,
        joined_at: now
      })
      |> Repo.insert!()

      room
    end)
    |> case do
      {:ok, room} -> {:ok, room}
      {:error, reason} -> {:error, Error.new(:internal_error, inspect(reason))}
    end
  end

  @spec join(String.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def join(app_key, room_id, user_id) do
    with {:ok, room} <- get(app_key, room_id) do
      if member?(app_key, room_id, user_id) do
        :ok
      else
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        Repo.transaction(fn ->
          %RoomMember{}
          |> RoomMember.changeset(%{
            app_key: app_key,
            room_id: room_id,
            user_id: user_id,
            joined_at: now
          })
          |> Repo.insert!()

          room
          |> Room.changeset(%{member_count: room.member_count + 1})
          |> Repo.update!()
        end)
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, Error.new(:internal_error, inspect(reason))}
        end
      end
    else
      {:error, :not_found} -> {:error, Error.new(:msg_invalid, "room not found")}
    end
  end

  @spec leave(String.t(), String.t(), String.t()) :: :ok
  def leave(app_key, room_id, user_id) do
    from(m in RoomMember,
      where: m.app_key == ^app_key and m.room_id == ^room_id and m.user_id == ^user_id
    )
    |> Repo.delete_all()

    case get(app_key, room_id) do
      {:ok, room} when room.member_count > 0 ->
        room
        |> Room.changeset(%{member_count: max(room.member_count - 1, 0)})
        |> Repo.update()

      _ ->
        :ok
    end

    :ok
  end

  @spec list_member_ids(String.t(), String.t()) :: [String.t()]
  def list_member_ids(app_key, room_id) do
    from(m in RoomMember,
      where: m.app_key == ^app_key and m.room_id == ^room_id,
      select: m.user_id
    )
    |> Repo.all()
  end

  @spec dismiss(String.t(), String.t()) :: :ok | {:error, :not_found}
  def dismiss(app_key, room_id) do
    case get(app_key, room_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, room} ->
        Repo.transaction(fn ->
          from(m in RoomMember, where: m.app_key == ^app_key and m.room_id == ^room_id)
          |> Repo.delete_all()

          Repo.delete!(room)
        end)

        :ok
    end
  end

  @spec remove_members(String.t(), String.t(), [String.t()]) ::
          {:ok, [String.t()]} | {:error, :not_found}
  def remove_members(app_key, room_id, uids) when is_list(uids) do
    with {:ok, room} <- get(app_key, room_id) do
      targets = uids |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()

      {n, _} =
        from(m in RoomMember,
          where: m.app_key == ^app_key and m.room_id == ^room_id and m.user_id in ^targets
        )
        |> Repo.delete_all()

      if n > 0 do
        room
        |> Room.changeset(%{member_count: max(room.member_count - n, 0)})
        |> Repo.update()
      end

      {:ok, targets}
    end
  end

  @spec update_meta(String.t(), String.t(), map()) ::
          {:ok, Room.t()} | {:error, :not_found | Error.t()}
  def update_meta(app_key, room_id, attrs) when is_map(attrs) do
    with {:ok, room} <- get(app_key, room_id) do
      room
      |> Room.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, r} -> {:ok, r}
        {:error, cs} -> {:error, Error.new(:msg_invalid, inspect(cs.errors))}
      end
    end
  end
end
