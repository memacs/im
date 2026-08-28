defmodule IM.Gateway.CidDedup do
  @moduledoc """
  同连接 `Packet.cid` 短窗去重（ETS，TTL 5 分钟）。与业务 `client_msg_id` 幂等分层。
  """

  use GenServer

  @table :im_cid_dedup
  @ttl_ms 5 * 60 * 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  若 cid 为空则不过滤。若已见过返回 `:duplicate`，否则登记并 `:ok`。

  ## 示例

      :ok = IM.Gateway.CidDedup.check("sess1", "cid-1")
      :duplicate = IM.Gateway.CidDedup.check("sess1", "cid-1")
  """
  @spec check(String.t(), String.t() | nil) :: :ok | :duplicate
  def check(_conn_id, cid) when cid in [nil, ""], do: :ok

  def check(conn_id, cid) when is_binary(conn_id) and is_binary(cid) do
    key = {conn_id, cid}
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, exp}] when exp > now ->
        :duplicate

      _ ->
        true = :ets.insert(@table, {key, now + @ttl_ms})
        :ok
    end
  end

  @impl true
  def init(_opts) do
    table =
      case :ets.whereis(@table) do
        :undefined -> :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        ref -> ref
      end

    schedule_sweep()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)

    :ets.select_delete(@table, [
      {
        {:"$1", :"$2"},
        [{:<, :"$2", now}],
        [true]
      }
    ])

    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, 60_000)
end
