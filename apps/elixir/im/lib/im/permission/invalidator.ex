defmodule IM.Permission.Invalidator do
  @moduledoc """
  订阅权限失效 PubSub，清除本节点 L1 ETS。
  """

  use GenServer

  alias IM.Permission.L1

  @topic "im:permission:invalidate"
  @pubsub IM.PubSub

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  广播失效事件到集群各节点。

  ## 示例

      IM.Permission.Invalidator.broadcast({:block, "a", "u1"})
  """
  @spec broadcast(term()) :: :ok
  def broadcast(event) do
    # 本节点同步清；再广播供其他节点 Invalidator 处理（本节点 handle_info 幂等）
    :ok = L1.invalidate(event)
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:permission_invalidate, event})
    :ok
  end

  @impl true
  def init(_opts) do
    :ok = Phoenix.PubSub.subscribe(@pubsub, @topic)
    :ok = L1.ensure_table!()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:permission_invalidate, event}, state) do
    :ok = L1.invalidate(event)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
