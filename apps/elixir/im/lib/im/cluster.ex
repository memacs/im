defmodule IM.Cluster do
  @moduledoc """
  集群拓扑配置（P9-01）。

  未配置 `CLUSTER_STRATEGY` 时不启动 libcluster（单节点开发/测试）。
  """

  @doc """
  返回 libcluster topologies；空列表表示不组网。

  ## 示例

      [] = IM.Cluster.topologies()
  """
  @spec topologies() :: keyword()
  def topologies do
    Application.get_env(:im, :cluster_topologies) ||
      Application.get_env(:libcluster, :topologies) ||
      []
  end

  @doc """
  是否启用集群发现。
  """
  @spec enabled?() :: boolean()
  def enabled?, do: topologies() != []
end
