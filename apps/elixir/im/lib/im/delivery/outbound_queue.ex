defmodule IM.Delivery.OutboundQueue do
  @moduledoc """
  单连接出站调度状态机（P3-09）：三带 WFQ + 老化 + burst + coalesce。

  挂在 `PacketTransport` 进程 state 内，非独立 GenServer。
  """

  alias IM.Protocol.{Codec, Push}
  alias Pb.Im.Protocol.{ChatMessage, CmdType, MsgPushBatch}

  @type band :: :high | :normal | :low

  @type item :: %{
          required(:packet_binary) => binary(),
          required(:priority) => band(),
          required(:inbox_seq) => non_neg_integer(),
          required(:enqueued_at_ms) => integer()
        }

  @type t :: %__MODULE__{
          high: [item()],
          normal: [item()],
          low: [item()],
          deficit: %{high: integer(), normal: integer(), low: integer()},
          last_band: band() | nil,
          burst_count: non_neg_integer(),
          depth: non_neg_integer(),
          dropped: non_neg_integer()
        }

  defstruct high: [],
            normal: [],
            low: [],
            deficit: %{high: 0, normal: 0, low: 0},
            last_band: nil,
            burst_count: 0,
            depth: 0,
            dropped: 0

  @doc "空队列。"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "当前积压条数。"
  @spec depth(t()) :: non_neg_integer()
  def depth(%__MODULE__{depth: d}), do: d

  @doc "是否为空。"
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{depth: 0}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc """
  入队。超过 `outbound_max_depth` 时丢弃最旧 LOW。

  ## 示例

      OutboundQueue.enqueue(q, %{packet_binary: bin, priority: :high, inbox_seq: 1, enqueued_at_ms: now})
  """
  @spec enqueue(t(), map()) :: t()
  def enqueue(%__MODULE__{} = q, item) when is_map(item) do
    band = normalize_priority(Map.get(item, :priority, :normal))

    entry = %{
      packet_binary: Map.fetch!(item, :packet_binary),
      priority: band,
      inbox_seq: Map.get(item, :inbox_seq, 0) || 0,
      enqueued_at_ms: Map.get(item, :enqueued_at_ms) || System.system_time(:millisecond)
    }

    q
    |> put_band(band, insert_sorted(get_band(q, band), entry))
    |> Map.update!(:depth, &(&1 + 1))
    |> maybe_drop_overflow()
  end

  @doc """
  取出最多 `max_n` 条待写二进制（已应用 aging / coalesce / WFQ / burst）。
  """
  @spec drain(t(), pos_integer()) :: {[binary()], t()}
  def drain(%__MODULE__{} = q, max_n) when is_integer(max_n) and max_n > 0 do
    now = System.system_time(:millisecond)

    q =
      q
      |> apply_aging(now)
      |> maybe_coalesce()

    do_drain(q, max_n, [], now)
  end

  defp maybe_coalesce(%__MODULE__{} = q) do
    depth = cfg(:outbound_coalesce_depth, 32)

    if q.depth > depth do
      high = coalesce_band(q.high)
      normal = coalesce_band(q.normal)
      low = coalesce_band(q.low)
      new_depth = length(high) + length(normal) + length(low)
      %{q | high: high, normal: normal, low: low, depth: new_depth}
    else
      q
    end
  end

  defp coalesce_band([]), do: []

  defp coalesce_band(items) do
    {result, buf} =
      Enum.reduce(items, {[], []}, fn item, {acc, buf} ->
        case extract_single_push(item.packet_binary) do
          {:ok, msg} ->
            {acc, buf ++ [{msg, item}]}

          :error ->
            {acc ++ flush_push_buf(buf) ++ [item], []}
        end
      end)

    result ++ flush_push_buf(buf)
  end

  defp flush_push_buf([]), do: []

  defp flush_push_buf(buf) do
    max = Application.get_env(:im, :push_batch_max, 50)

    buf
    |> Enum.chunk_every(max)
    |> Enum.flat_map(fn chunk ->
      case encode_coalesced(chunk) do
        {:ok, item} -> [item]
        :error -> Enum.map(chunk, fn {_msg, item} -> item end)
      end
    end)
  end

  defp encode_coalesced([{_msg, sole}]) do
    {:ok, sole}
  end

  defp encode_coalesced(chunk) when length(chunk) > 1 do
    messages = Enum.map(chunk, fn {msg, _} -> msg end)
    {_msg, head} = hd(chunk)
    batch = %MsgPushBatch{messages: messages}

    with {:ok, packet} <-
           Push.build(:CMD_MSG_PUSH_BATCH, batch, route_key: hd(messages).conv_id || ""),
         {:ok, bin} <- Codec.encode(packet) do
      {:ok,
       %{
         packet_binary: bin,
         priority: head.priority,
         inbox_seq: head.inbox_seq,
         enqueued_at_ms: head.enqueued_at_ms
       }}
    else
      _ -> :error
    end
  end

  defp extract_single_push(bin) when is_binary(bin) do
    push_cmd = CmdType.value(:CMD_MSG_PUSH)

    try do
      case Codec.decode(bin) do
        {:ok, %{cmd: ^push_cmd, payload: payload}} when is_binary(payload) and payload != <<>> ->
          {:ok, ChatMessage.decode(payload)}

        _ ->
          :error
      end
    rescue
      _ -> :error
    end
  end

  defp do_drain(q, 0, acc, _now), do: {Enum.reverse(acc), q}
  defp do_drain(%__MODULE__{depth: 0} = q, _n, acc, _now), do: {Enum.reverse(acc), q}

  defp do_drain(q, n, acc, now) do
    case pick_next(q) do
      {nil, q2} ->
        {Enum.reverse(acc), q2}

      {item, q2} ->
        wait = max(now - item.enqueued_at_ms, 0)
        IM.Telemetry.Outbound.wait_ms(wait, item.priority)
        do_drain(q2, n - 1, [item.packet_binary | acc], now)
    end
  end

  defp pick_next(q) do
    case nonempty_bands(q) do
      [] ->
        {nil, q}

      bands ->
        band = select_band(q, bands)
        [item | rest] = get_band(q, band)
        sum_w = weight_sum()

        deficit =
          q.deficit
          |> Map.update!(band, &(&1 - sum_w))
          |> Map.update!(band, &(&1 + weight(band)))

        burst_count = if q.last_band == band, do: q.burst_count + 1, else: 1

        q2 =
          q
          |> put_band(band, rest)
          |> Map.put(:deficit, deficit)
          |> Map.put(:last_band, band)
          |> Map.put(:burst_count, burst_count)
          |> Map.update!(:depth, &(&1 - 1))

        {item, q2}
    end
  end

  defp select_band(q, bands) do
    max_burst = cfg(:priority_max_burst, 16)

    if q.last_band && q.burst_count >= max_burst do
      case Enum.reject(bands, &(&1 == q.last_band)) do
        [] -> best_deficit(q, bands)
        others -> best_deficit(q, others)
      end
    else
      best_deficit(q, bands)
    end
  end

  defp best_deficit(q, bands) do
    bands
    |> Enum.sort_by(fn b -> {-Map.fetch!(q.deficit, b), band_rank(b)} end)
    |> hd()
  end

  defp apply_aging(q, now) do
    low_to_high = cfg(:priority_aging_low_to_high_ms, 5_000)
    low_to_normal = cfg(:priority_aging_low_ms, 2_000)
    normal_to_high = cfg(:priority_aging_normal_ms, 500)

    {low_keep, to_high_from_low, to_normal_from_low} =
      Enum.reduce(q.low, {[], [], []}, fn item, {keep, hi, no} ->
        wait = now - item.enqueued_at_ms

        cond do
          wait >= low_to_high -> {keep, [item | hi], no}
          wait >= low_to_normal -> {keep, hi, [item | no]}
          true -> {[item | keep], hi, no}
        end
      end)

    {normal_keep, to_high_from_normal} =
      Enum.reduce(q.normal, {[], []}, fn item, {keep, hi} ->
        if now - item.enqueued_at_ms >= normal_to_high do
          {keep, [item | hi]}
        else
          {[item | keep], hi}
        end
      end)

    high =
      q.high
      |> insert_many(Enum.reverse(to_high_from_low))
      |> insert_many(Enum.reverse(to_high_from_normal))

    normal =
      Enum.reverse(normal_keep)
      |> insert_many(Enum.reverse(to_normal_from_low))

    if to_high_from_low != [],
      do: IM.Telemetry.Outbound.aged(:low, :high, length(to_high_from_low))

    if to_normal_from_low != [],
      do: IM.Telemetry.Outbound.aged(:low, :normal, length(to_normal_from_low))

    if to_high_from_normal != [],
      do: IM.Telemetry.Outbound.aged(:normal, :high, length(to_high_from_normal))

    %{q | high: high, normal: normal, low: Enum.reverse(low_keep)}
  end

  defp maybe_drop_overflow(%__MODULE__{} = q) do
    max = cfg(:outbound_max_depth, 10_000)

    if q.depth <= max or q.low == [] do
      q
    else
      [_old | rest] = q.low

      :telemetry.execute(
        [:im, :outbound, :dropped],
        %{count: 1},
        %{priority: :low, host: IM.Telemetry.Tags.host()}
      )

      maybe_drop_overflow(%{q | low: rest, depth: q.depth - 1, dropped: q.dropped + 1})
    end
  end

  defp insert_sorted([], item), do: [item]

  defp insert_sorted([h | t] = list, item) do
    if {item.inbox_seq, item.enqueued_at_ms} <= {h.inbox_seq, h.enqueued_at_ms} do
      [item | list]
    else
      [h | insert_sorted(t, item)]
    end
  end

  defp insert_many(list, items), do: Enum.reduce(items, list, &insert_sorted(&2, &1))

  defp get_band(q, :high), do: q.high
  defp get_band(q, :normal), do: q.normal
  defp get_band(q, :low), do: q.low

  defp put_band(q, :high, items), do: %{q | high: items}
  defp put_band(q, :normal, items), do: %{q | normal: items}
  defp put_band(q, :low, items), do: %{q | low: items}

  defp nonempty_bands(q) do
    []
    |> maybe_band(:high, q.high)
    |> maybe_band(:normal, q.normal)
    |> maybe_band(:low, q.low)
  end

  defp maybe_band(acc, _b, []), do: acc
  defp maybe_band(acc, b, _), do: acc ++ [b]

  defp weight(:high), do: cfg(:priority_weight_high, 8)
  defp weight(:normal), do: cfg(:priority_weight_normal, 4)
  defp weight(:low), do: cfg(:priority_weight_low, 1)
  defp weight_sum, do: weight(:high) + weight(:normal) + weight(:low)

  defp band_rank(:high), do: 0
  defp band_rank(:normal), do: 1
  defp band_rank(:low), do: 2

  def normalize_priority(:high), do: :high
  def normalize_priority(:MSG_PRIORITY_HIGH), do: :high
  def normalize_priority(1), do: :high
  def normalize_priority(:normal), do: :normal
  def normalize_priority(:MSG_PRIORITY_NORMAL), do: :normal
  def normalize_priority(0), do: :normal
  def normalize_priority(:low), do: :low
  def normalize_priority(:MSG_PRIORITY_LOW), do: :low
  def normalize_priority(2), do: :low
  def normalize_priority(_), do: :normal

  defp cfg(key, default), do: Application.get_env(:im, key, default)
end
