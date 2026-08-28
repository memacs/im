defmodule IM.Cluster.RouterTest do
  use ExUnit.Case, async: false

  alias IM.Cluster.Router

  setup do
    prev_nodes = Application.get_env(:im, :message_nodes)
    prev_role = Application.get_env(:im, :node_role)

    on_exit(fn ->
      restore(:message_nodes, prev_nodes)
      restore(:node_role, prev_role)
    end)

    :ok
  end

  test "同一 route_key 稳定映射到同一节点" do
    Application.put_env(:im, :message_nodes, [:a@localhost, :b@localhost, :c@localhost])

    n1 = Router.owner("g:100")
    n2 = Router.owner("g:100")
    assert n1 == n2
    assert n1 in [:a@localhost, :b@localhost, :c@localhost]
  end

  test "不同 key 可分散到不同节点" do
    Application.put_env(:im, :message_nodes, [:a@localhost, :b@localhost])

    owners =
      1..40
      |> Enum.map(fn i -> Router.owner("conv-#{i}") end)
      |> Enum.uniq()

    assert length(owners) == 2
  end

  test "role=all 时 local? 恒为 true" do
    Application.put_env(:im, :node_role, "all")
    assert Router.local?("anything")
  end

  test "call 本机直接 apply" do
    assert 3 = Router.call("k", __MODULE__, :add, [1, 2])
  end

  def add(a, b), do: a + b

  defp restore(key, nil), do: Application.delete_env(:im, key)
  defp restore(key, val), do: Application.put_env(:im, key, val)
end
