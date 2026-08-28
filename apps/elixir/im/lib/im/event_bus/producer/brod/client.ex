defmodule IM.EventBus.Producer.Brod.Client do
  @moduledoc """
  在监督树中启动 / 停止 brod client（`auto_start_producers: true`）。

  仅当 `event_bus_producer` 为 `Brod` 且配置了 brokers 时由 `IM.Application` 挂载。
  """

  use GenServer

  @doc """
  启动 Client GenServer。

  ## 示例

      {:ok, _pid} = IM.EventBus.Producer.Brod.Client.start_link([])
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    brokers = Keyword.get(opts, :brokers) || IM.EventBus.Producer.Brod.brokers()
    client_id = Keyword.get(opts, :client_id) || IM.EventBus.Producer.Brod.client_id()

    if brokers == [] do
      {:stop, :kafka_not_configured}
    else
      endpoints = normalize_endpoints(brokers)

      case start_client(endpoints, client_id, client_config()) do
        :ok ->
          {:ok, %{client_id: client_id}}

        {:error, {:already_started, _}} ->
          {:ok, %{client_id: client_id}}

        {:error, reason} ->
          {:stop, reason}
      end
    end
  end

  @impl true
  def terminate(_reason, %{client_id: client_id}) do
    _ = stop_client(client_id)
    :ok
  end

  defp start_client(endpoints, client_id, config) do
    adapter = Application.get_env(:im, :brod_adapter, :brod)

    if function_exported?(adapter, :start_client, 3) do
      adapter.start_client(endpoints, client_id, config)
    else
      :brod.start_client(endpoints, client_id, config)
    end
  end

  defp stop_client(client_id) do
    adapter = Application.get_env(:im, :brod_adapter, :brod)

    cond do
      function_exported?(adapter, :stop_client, 1) -> adapter.stop_client(client_id)
      adapter == :brod -> :brod.stop_client(client_id)
      true -> :ok
    end
  end

  defp client_config do
    conf = Application.get_env(:im, :event_bus_kafka, [])

    [
      auto_start_producers: true,
      reconnect_cool_down_seconds: Keyword.get(conf, :reconnect_cool_down_seconds, 5),
      default_producer_config: [
        required_acks: Keyword.get(conf, :required_acks, -1)
      ]
    ]
  end

  defp normalize_endpoints(brokers) do
    Enum.map(brokers, fn
      {host, port} when is_binary(host) and is_integer(port) ->
        {String.to_charlist(host), port}

      {host, port} when is_list(host) and is_integer(port) ->
        {host, port}

      other ->
        other
    end)
  end
end
