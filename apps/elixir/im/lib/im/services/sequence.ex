defmodule IM.Services.Sequence do
  @moduledoc """
  序号分配（P9-02：Redis/Cache 权威，PostgreSQL 兜底）。

  支持 `conv_seq` / `inbox_seq` / `msg_id_fallback`。
  Redis 键：`im:{app_key}:seq:conv|{inbox}:{key}`（hash tag 为 app_key）。
  """

  alias IM.Cache
  alias IM.Repo

  @doc """
  递增并返回下一个序号。

  ## 示例

      IM.Services.Sequence.next("app", "conv_seq", "p:a:b")
  """
  @spec next(String.t(), String.t(), String.t()) :: pos_integer()
  def next(app_key, seq_type, seq_key)
      when is_binary(app_key) and is_binary(seq_type) and is_binary(seq_key) do
    if Cache.enabled?() do
      case cache_next(app_key, seq_type, seq_key) do
        {:ok, val} ->
          # 异步对齐 PG 兜底水位（失败忽略，不阻塞热路径）
          _ = sync_postgres_async(app_key, seq_type, seq_key, val)
          val

        {:error, _} ->
          postgres_next(app_key, seq_type, seq_key)
      end
    else
      postgres_next(app_key, seq_type, seq_key)
    end
  end

  defp cache_next(app_key, seq_type, seq_key) do
    key = redis_key(app_key, seq_type, seq_key)

    with {:ok, existing} <- Cache.get(key),
         :ok <- maybe_seed(key, existing, app_key, seq_type, seq_key) do
      Cache.incr(key)
    end
  end

  defp maybe_seed(_key, existing, _app, _type, _seq) when not is_nil(existing), do: :ok

  defp maybe_seed(key, nil, app_key, seq_type, seq_key) do
    seed = postgres_current(app_key, seq_type, seq_key)
    Cache.set(key, Integer.to_string(seed))
  end

  defp redis_key(app_key, "conv_seq", seq_key), do: "im:{#{app_key}}:seq:conv:#{seq_key}"
  defp redis_key(app_key, "inbox_seq", seq_key), do: "im:{#{app_key}}:seq:inbox:#{seq_key}"

  defp redis_key(app_key, seq_type, seq_key),
    do: "im:{#{app_key}}:seq:#{seq_type}:#{seq_key}"

  defp postgres_current(app_key, seq_type, seq_key) do
    case Repo.query(
           """
           SELECT current_val FROM msg_sequences
           WHERE app_key = $1 AND seq_type = $2 AND seq_key = $3
           """,
           [app_key, seq_type, seq_key]
         ) do
      {:ok, %{rows: [[val]]}} when is_integer(val) -> val
      _ -> 0
    end
  end

  defp postgres_next(app_key, seq_type, seq_key) do
    %{rows: [[val]]} =
      Repo.query!(
        """
        INSERT INTO msg_sequences (app_key, seq_type, seq_key, current_val, updated_at)
        VALUES ($1, $2, $3, 1, NOW())
        ON CONFLICT (app_key, seq_type, seq_key)
        DO UPDATE SET current_val = msg_sequences.current_val + 1, updated_at = NOW()
        RETURNING current_val
        """,
        [app_key, seq_type, seq_key]
      )

    val
  end

  defp sync_postgres_async(app_key, seq_type, seq_key, val) do
    if Application.get_env(:im, :sequence_pg_sync, true) do
      Task.Supervisor.start_child(IM.TaskSupervisor, fn ->
        _ =
          Repo.query(
            """
            INSERT INTO msg_sequences (app_key, seq_type, seq_key, current_val, updated_at)
            VALUES ($1, $2, $3, $4, NOW())
            ON CONFLICT (app_key, seq_type, seq_key)
            DO UPDATE SET
              current_val = GREATEST(msg_sequences.current_val, EXCLUDED.current_val),
              updated_at = NOW()
            """,
            [app_key, seq_type, seq_key, val]
          )
      end)
    else
      :ok
    end
  end
end
