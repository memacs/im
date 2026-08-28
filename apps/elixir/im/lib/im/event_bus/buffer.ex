defmodule IM.EventBus.Buffer do
  @moduledoc """
  旁路内存队列：入队 + drain 到 `IM.EventBus.Producer`。
  """

  use GenServer

  alias IM.EventBus.Kafka

  @max_default 10_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec enqueue(atom(), map()) :: :ok
  def enqueue(topic, event) when is_atom(topic) and is_map(event) do
    GenServer.cast(__MODULE__, {:enqueue, topic, event})
  end

  @doc "同步入队并刷到 Producer（避免 cast 竞态）。"
  @spec enqueue_and_flush(atom(), map(), pos_integer()) :: non_neg_integer()
  def enqueue_and_flush(topic, event, n \\ 100)
      when is_atom(topic) and is_map(event) and is_integer(n) and n > 0 do
    GenServer.call(__MODULE__, {:enqueue_and_flush, topic, event, n})
  end

  @doc "测试/运维：取出当前队列快照。"
  @spec snapshot() :: [{atom(), map()}]
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @doc "将最多 `n` 条刷到 Producer；返回刷出条数。"
  @spec flush_to_producer(pos_integer()) :: non_neg_integer()
  def flush_to_producer(n \\ 100) when is_integer(n) and n > 0 do
    GenServer.call(__MODULE__, {:flush, n})
  end

  @impl true
  def init(opts) do
    max = Keyword.get(opts, :max_len, Application.get_env(:im, :event_bus_buffer_max, @max_default))
    {:ok, %{q: :queue.new(), len: 0, max: max}}
  end

  @impl true
  def handle_cast({:enqueue, topic, event}, state) do
    q = :queue.in({topic, event}, state.q)
    len = state.len + 1

    {q, len} =
      if len > state.max do
        {{:value, _}, q2} = :queue.out(q)
        :telemetry.execute([:im, :event_bus, :drop], %{count: 1}, %{topic: topic})
        {q2, state.max}
      else
        {q, len}
      end

    :telemetry.execute([:im, :event_bus, :enqueue], %{count: 1}, %{topic: topic})
    {:noreply, %{state | q: q, len: len}}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, :queue.to_list(state.q), state}
  end

  def handle_call({:enqueue_and_flush, topic, event, n}, _from, state) do
    {:noreply, state2} = handle_cast({:enqueue, topic, event}, state)
    handle_call({:flush, n}, :from, state2)
  end

  def handle_call({:flush, n}, _from, state) do
    {batch, q, len} = take_n(state.q, state.len, n, [])

    Enum.each(batch, fn {topic, event} ->
      _ = Kafka.encode_and_produce(topic, event)
    end)

    {:reply, length(batch), %{state | q: q, len: len}}
  end

  defp take_n(q, len, 0, acc), do: {Enum.reverse(acc), q, len}
  defp take_n(q, 0, _n, acc), do: {Enum.reverse(acc), q, 0}

  defp take_n(q, len, n, acc) do
    case :queue.out(q) do
      {{:value, item}, q2} -> take_n(q2, len - 1, n - 1, [item | acc])
      {:empty, q2} -> {Enum.reverse(acc), q2, 0}
    end
  end
end
