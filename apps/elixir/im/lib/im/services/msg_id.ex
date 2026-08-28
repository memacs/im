defmodule IM.Services.MsgId do
  @moduledoc """
  `msg_id` Snowflake 发号（DD-039）。

  启动时经 `IM.Services.MsgId.Lease` 占用 `worker_id`；失败或时钟回拨过大则走 PG 兜底（T=1）。
  """

  use GenServer

  alias IM.Services.MsgId.Lease
  alias IM.Services.Sequence

  @epoch_ms 1_704_067_200_000
  @max_sequence 0xFFF

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  生成十进制字符串 `msg_id`。

  ## 示例

      msg_id = IM.Services.MsgId.next("app_key")
  """
  @spec next(String.t()) :: String.t()
  def next(app_key) when is_binary(app_key) do
    GenServer.call(__MODULE__, {:next, app_key})
  end

  @doc "当前持有的 worker_id（测试用）；无租约返回 nil。"
  @spec worker_id() :: non_neg_integer() | nil
  def worker_id do
    GenServer.call(__MODULE__, :worker_id)
  end

  @impl true
  def init(_opts) do
    mode = Application.get_env(:im, :msg_id_mode, :snowflake)

    state =
      case mode do
        :pg_fallback ->
          %{worker_id: nil, last_ts: 0, seq: 0, node_name: node_str()}

        _ ->
          case Lease.acquire() do
            {:ok, id} ->
              Process.send_after(self(), :renew_lease, Lease.renew_ms())
              %{worker_id: id, last_ts: 0, seq: 0, node_name: node_str()}

            {:error, :no_worker} ->
              %{worker_id: nil, last_ts: 0, seq: 0, node_name: node_str()}
          end
      end

    {:ok, state}
  end

  @impl true
  def terminate(_reason, %{worker_id: id, node_name: node}) when is_integer(id) do
    Lease.release(id, node)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  @impl true
  def handle_info(:renew_lease, %{worker_id: id, node_name: node} = state) when is_integer(id) do
    case Lease.renew(id, node) do
      :ok ->
        Process.send_after(self(), :renew_lease, Lease.renew_ms())
        {:noreply, state}

      {:error, _} ->
        {:noreply, %{state | worker_id: nil}}
    end
  end

  def handle_info(:renew_lease, state), do: {:noreply, state}

  @impl true
  def handle_call(:worker_id, _from, state), do: {:reply, state.worker_id, state}

  def handle_call({:next, app_key}, _from, %{worker_id: nil} = state) do
    {:reply, fallback_id(app_key), state}
  end

  def handle_call({:next, app_key}, _from, state) do
    now = System.system_time(:millisecond)

    cond do
      now < state.last_ts - 5 ->
        {:reply, fallback_id(app_key), state}

      now == state.last_ts and state.seq >= @max_sequence ->
        # 同毫秒 Snowflake 序号用尽，让步 1ms 以切换时间戳
        Process.sleep(1)
        {:reply, snowflake(now + 1, state.worker_id, 0), %{state | last_ts: now + 1, seq: 0}}

      now == state.last_ts ->
        seq = state.seq + 1
        {:reply, snowflake(now, state.worker_id, seq), %{state | seq: seq}}

      true ->
        {:reply, snowflake(now, state.worker_id, 0), %{state | last_ts: now, seq: 0}}
    end
  end

  defp snowflake(ts_ms, worker_id, seq) do
    ts = ts_ms - @epoch_ms
    id = Bitwise.bsl(ts, 22) |> Bitwise.bor(Bitwise.bsl(worker_id, 12)) |> Bitwise.bor(seq)
    Integer.to_string(id)
  end

  defp fallback_id(app_key) do
    counter = Sequence.next(app_key, "msg_id_fallback", "__global__")
    id = Bitwise.bor(Bitwise.bsl(1, 62), counter)
    Integer.to_string(id)
  end

  defp node_str, do: Atom.to_string(Node.self())
end
