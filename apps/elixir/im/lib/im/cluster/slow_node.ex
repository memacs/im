defmodule IM.Cluster.SlowNode do
  @moduledoc "树状扇出慢节点隔离（ETS）。"

  use GenServer

  @table :im_tree_slow_nodes

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  标记慢节点，隔离 `slow_isolate_sec`。

  ## 示例

      IM.Cluster.SlowNode.mark(node(), 30)
  """
  @spec mark(node(), pos_integer()) :: :ok
  def mark(node, isolate_sec) when is_atom(node) and isolate_sec > 0 do
    exp = System.monotonic_time(:millisecond) + isolate_sec * 1000
    true = :ets.insert(@table, {node, exp})
    :telemetry.execute([:im, :group, :tree_slow_node], %{count: 1}, %{node: node})
    :ok
  end

  @doc """
  节点是否在隔离窗内。
  """
  @spec isolated?(node()) :: boolean()
  def isolated?(node) when is_atom(node) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, node) do
      [{^node, exp}] when exp > now -> true
      [{^node, _}] ->
        :ets.delete(@table, node)
        false

      _ ->
        false
    end
  end

  @impl true
  def init(_opts) do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
      _ -> :ok
    end

    {:ok, %{}}
  end
end
