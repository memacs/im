defmodule IM.AppConfig.Invalidator do
  @moduledoc """
  订阅 AppConfig 失效 PubSub，清除本节点 ETS 缓存。
  """

  use GenServer

  alias IM.Stores.AppConfigStore

  @topic "im:app_config:invalidate"
  @pubsub IM.PubSub

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  广播配置失效到集群各节点。

  ## 示例

      IM.AppConfig.Invalidator.broadcast("a", "friend", "require_friend_to_send")
  """
  @spec broadcast(String.t(), String.t(), String.t()) :: :ok
  def broadcast(app_key, category, key)
      when is_binary(app_key) and is_binary(category) and is_binary(key) do
    :ok = AppConfigStore.invalidate_local(app_key, category, key)

    Phoenix.PubSub.broadcast(
      @pubsub,
      @topic,
      {:app_config_invalidate, {app_key, category, key}}
    )

    :ok
  end

  @impl true
  def init(_opts) do
    :ok = Phoenix.PubSub.subscribe(@pubsub, @topic)
    :ok = AppConfigStore.ensure_table()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:app_config_invalidate, {app_key, category, key}}, state) do
    :ok = AppConfigStore.invalidate_local(app_key, category, key)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
