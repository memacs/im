defmodule IM.EventBus.Producer.Brod do
  @moduledoc """
  经 [brod](https://hex.pm/packages/brod) 写入真实 Kafka。

  配置见 `:im` / `:event_bus_kafka` 的 `brokers`、`client_id`；
  测试可设 `Application.put_env(:im, :brod_adapter, FakeModule)`。
  """

  @behaviour IM.EventBus.Producer

  @doc "读取配置的 bootstrap brokers（`[{host, port}, ...]`）。"
  @spec brokers() :: [{binary() | charlist(), pos_integer()}]
  def brokers do
    conf = Application.get_env(:im, :event_bus_kafka, [])
    Keyword.get(conf, :brokers, [])
  end

  @doc """
  解析 `KAFKA_BROKERS` 环境变量（`host:port,host2:port2`）。

  ## 示例

      [{"kafka", 9092}] = IM.EventBus.Producer.Brod.parse_brokers("kafka:9092")
  """
  @spec parse_brokers(String.t() | nil) :: [{String.t(), pos_integer()}]
  def parse_brokers(nil), do: []
  def parse_brokers(""), do: []

  def parse_brokers(raw) when is_binary(raw) do
    raw
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn hostport ->
      case String.split(hostport, ":", parts: 2) do
        [host, port] ->
          case Integer.parse(port) do
            {p, ""} when p > 0 -> [{host, p}]
            _ -> []
          end

        _ ->
          []
      end
    end)
  end


  @doc "brod client id（atom）。"
  @spec client_id() :: atom()
  def client_id do
    conf = Application.get_env(:im, :event_bus_kafka, [])
    Keyword.get(conf, :client_id, :im_kafka)
  end

  @doc """
  产出一条记录。

  ## Options

  - `:key` — 分区键（binary，默认 `\"\"`）
  - `:partition` — 分区或 `:hash` / `:random`（默认 `:hash`）

  ## 示例

      IM.EventBus.Producer.Brod.produce("im.upstream", <<1, 2>>, key: "m1")
  """
  def produce(topic, payload) when is_binary(topic) and is_binary(payload) do
    produce(topic, payload, [])
  end

  @impl true
  def produce(topic, payload, opts)
      when is_binary(topic) and is_binary(payload) and is_list(opts) do
    if brokers() == [] do
      {:error, :kafka_not_configured}
    else
      client = client_id()
      key = normalize_key(Keyword.get(opts, :key, ""))
      partition = Keyword.get(opts, :partition, :hash)

      case adapter().produce_sync(client, topic, partition, key, payload) do
        :ok ->
          :telemetry.execute([:im, :event_bus, :produce], %{count: 1}, %{topic: topic, backend: :brod})
          :ok

        {:ok, _offset} ->
          :telemetry.execute([:im, :event_bus, :produce], %{count: 1}, %{topic: topic, backend: :brod})
          :ok

        {:error, reason} = err ->
          :telemetry.execute([:im, :event_bus, :produce_error], %{count: 1}, %{
            topic: topic,
            reason: inspect(reason),
            backend: :brod
          })

          err
      end
    end
  end

  defp adapter do
    Application.get_env(:im, :brod_adapter, :brod)
  end

  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_integer(key), do: Integer.to_string(key)
  defp normalize_key(_), do: ""
end
