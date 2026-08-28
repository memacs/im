defmodule IM.Group.FanoutConfig do
  @moduledoc "群扇出可配置参数（design/group.md §5.1）。"

  @defaults [
    tree_threshold: 500,
    branching_factor: 8,
    max_depth: 4,
    rpc_timeout_ms: 2000,
    recipients_chunk: 200,
    coordinator_parallelism: 8,
    slow_node_ms: 500,
    slow_isolate_sec: 30,
    retry_max: 1,
    inbox_insert_chunk: 500,
    read_fanout_enabled: true,
    read_fanout_threshold: 500
  ]

  @doc """
  读取配置项。

  ## 示例

      IM.Group.FanoutConfig.get(:tree_threshold)
  """
  @spec get(atom()) :: term()
  def get(key) when is_atom(key) do
    conf = Application.get_env(:im, :group_fanout, [])
    Keyword.get(conf, key, Keyword.fetch!(@defaults, key))
  end

  @doc """
  `push_batch_max`（全局）。
  """
  @spec push_batch_max() :: pos_integer()
  def push_batch_max do
    Application.get_env(:im, :push_batch_max, 50)
  end
end
