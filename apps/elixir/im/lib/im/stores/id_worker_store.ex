defmodule IM.Stores.IdWorkerStore do
  @moduledoc "`id_workers` 表读写（MsgId 租约镜像）。"

  import Ecto.Query

  alias IM.Repo
  alias IM.Schemas.IdWorker

  @doc """
  写入或更新租约镜像。

  ## 示例

      :ok = IM.Stores.IdWorkerStore.upsert(3, "im@127.0.0.1", ~U[2000-01-01 00:00:30.000000Z])
  """
  @spec upsert(non_neg_integer(), String.t(), DateTime.t()) :: :ok | {:error, term()}
  def upsert(worker_id, node_name, lease_until)
      when is_integer(worker_id) and is_binary(node_name) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    lease_until = DateTime.truncate(lease_until, :microsecond)

    %IdWorker{}
    |> IdWorker.changeset(%{
      worker_id: worker_id,
      node_name: node_name,
      lease_until: lease_until,
      updated_at: now
    })
    |> Repo.insert(
      on_conflict: {:replace, [:node_name, :lease_until, :updated_at]},
      conflict_target: [:worker_id]
    )
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "删除租约镜像。"
  @spec delete(non_neg_integer()) :: :ok
  def delete(worker_id) when is_integer(worker_id) do
    _ = Repo.delete_all(from(w in IdWorker, where: w.worker_id == ^worker_id))
    :ok
  end
end
