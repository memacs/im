defmodule IM.ClusterTest do
  use ExUnit.Case, async: true

  test "默认未配置 topologies，不启用集群" do
    assert IM.Cluster.topologies() == []
    refute IM.Cluster.enabled?()
  end

  test "可注入 topologies" do
    previous = Application.get_env(:im, :cluster_topologies)

    Application.put_env(:im, :cluster_topologies,
      im: [
        strategy: Cluster.Strategy.Epmd,
        config: [hosts: [:"im@127.0.0.1"]]
      ]
    )

    try do
      assert IM.Cluster.enabled?()
      assert Keyword.has_key?(IM.Cluster.topologies(), :im)
    after
      if previous do
        Application.put_env(:im, :cluster_topologies, previous)
      else
        Application.delete_env(:im, :cluster_topologies)
      end
    end
  end
end
