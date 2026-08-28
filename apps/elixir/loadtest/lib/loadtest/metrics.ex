defmodule IM.LoadTest.Metrics do
  @moduledoc "ETS 采样：成功/失败计数与延迟样本。"

  use GenServer

  @table :im_loadtest_metrics

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "重置计数与样本。"
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc "记录一次成功操作及其延迟（毫秒）。"
  def success(op, latency_ms) when is_atom(op) and is_number(latency_ms) do
    :ets.update_counter(@table, {:ok, op}, {2, 1}, {{:ok, op}, 0})
    :ets.insert(@table, {{:sample, op, System.unique_integer([:positive])}, latency_ms})
    :ok
  end

  @doc "记录失败（可选错误标签）。"
  def failure(op, reason \\ :error) when is_atom(op) do
    :ets.update_counter(@table, {:err, op}, {2, 1}, {{:err, op}, 0})
    key = {:err_reason, op, inspect(reason)}
    :ets.update_counter(@table, key, {2, 1}, {key, 0})
    :ok
  end

  @doc "导出原始快照供 Reporter 使用。"
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @impl true
  def init(_opts) do
    table =
      case :ets.whereis(@table) do
        :undefined ->
          :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])

        tid ->
          tid
      end

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  def handle_call(:snapshot, _from, state) do
    rows = :ets.tab2list(@table)
    {:reply, rows, state}
  end
end
