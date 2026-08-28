defmodule IM.Stores.PassthroughStore do
  @moduledoc "透传消息暂存。"

  import Ecto.Query

  alias IM.Domain.Error
  alias IM.Repo
  alias IM.Schemas.PassthroughMessage

  @spec insert(map()) :: {:ok, PassthroughMessage.t()} | {:error, Error.t()}
  def insert(attrs) when is_map(attrs) do
    %PassthroughMessage{}
    |> PassthroughMessage.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, row} -> {:ok, row}
      {:error, cs} -> {:error, Error.new(:internal_error, inspect(cs.errors))}
    end
  end

  @spec list_pending(String.t(), String.t()) :: [PassthroughMessage.t()]
  def list_pending(app_key, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    from(p in PassthroughMessage,
      where: p.app_key == ^app_key and p.user_id == ^user_id and p.expires_at > ^now,
      order_by: [asc: p.created_at]
    )
    |> Repo.all()
  end

  @spec delete_expired(pos_integer()) :: non_neg_integer()
  def delete_expired(limit \\ 500) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    ids =
      from(p in PassthroughMessage,
        where: p.expires_at < ^now,
        select: p.id,
        limit: ^limit
      )
      |> Repo.all()

    {count, _} =
      from(p in PassthroughMessage, where: p.id in ^ids)
      |> Repo.delete_all()

    count
  end
end
