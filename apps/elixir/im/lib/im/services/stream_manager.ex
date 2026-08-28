defmodule IM.Services.StreamManager do
  @moduledoc """
  流式消息（MSG_STREAM）状态：跟踪 `stream_id`、校验序号、汇总文本。

  每块仍由 `IM.Services.Message` 落库；本模块只做内存侧顺序与生命周期。
  """

  use GenServer

  alias IM.Domain.Error
  alias Pb.Im.Protocol.StreamContent

  @type meta :: %{
          optional(:conv_id) => String.t(),
          optional(:from) => String.t(),
          optional(:to) => String.t()
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc "登记一块流内容；成功返回 `:ok`。"
  @spec track_chunk(String.t(), StreamContent.t(), meta()) :: :ok | {:error, Error.t()}
  def track_chunk(app_key, %StreamContent{} = sc, meta \\ %{}) when is_binary(app_key) do
    GenServer.call(__MODULE__, {:track, app_key, sc, meta})
  end

  @doc "按 sequence 拼接已登记 chunk 文本。"
  @spec assembled_text(String.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def assembled_text(app_key, stream_id) do
    GenServer.call(__MODULE__, {:assembled, app_key, stream_id})
  end

  @doc "测试辅助：清空状态。"
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call({:track, app_key, sc, meta}, _from, state) do
    key = {app_key, sc.stream_id}

    case validate_and_update(Map.get(state, key), sc, meta) do
      {:ok, entry} ->
        {:reply, :ok, Map.put(state, key, entry)}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  def handle_call({:assembled, app_key, stream_id}, _from, state) do
    case Map.get(state, {app_key, stream_id}) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{chunks: chunks} ->
        text =
          chunks
          |> Enum.sort_by(fn {seq, _} -> seq end)
          |> Enum.map(fn {_, c} -> c end)
          |> Enum.join()

        {:reply, {:ok, text}, state}
    end
  end

  def handle_call(:reset, _from, _state), do: {:reply, :ok, %{}}

  defp validate_and_update(nil, %StreamContent{stream_id: id}, _meta)
       when id == "" or is_nil(id) do
    {:error, Error.new(:msg_invalid, "stream_id required")}
  end

  defp validate_and_update(nil, %StreamContent{} = sc, meta) do
    if terminal?(sc.status) and sc.status != :STREAM_STATUS_START do
      # 允许直接 END（短流），仍登记
      {:ok, new_entry(sc, meta, closed?: terminal?(sc.status))}
    else
      {:ok, new_entry(sc, meta, closed?: false)}
    end
  end

  defp validate_and_update(%{closed?: true}, %StreamContent{status: status}, _meta)
       when status in [:STREAM_STATUS_ONGOING, :STREAM_STATUS_START] do
    {:error, Error.new(:msg_invalid, "stream already closed")}
  end

  defp validate_and_update(%{last_seq: last} = entry, %StreamContent{} = sc, _meta) do
    cond do
      sc.stream_id == "" ->
        {:error, Error.new(:msg_invalid, "stream_id required")}

      sc.sequence <= last and sc.status == :STREAM_STATUS_ONGOING ->
        {:error, Error.new(:msg_invalid, "stream sequence must increase")}

      true ->
        chunks =
          if sc.chunk != "" do
            Map.put(entry.chunks, sc.sequence, sc.chunk)
          else
            entry.chunks
          end

        {:ok,
         %{
           entry
           | last_seq: max(entry.last_seq, sc.sequence),
             chunks: chunks,
             status: sc.status,
             closed?: terminal?(sc.status)
         }}
    end
  end

  defp new_entry(sc, meta, closed?: closed?) do
    chunks = if sc.chunk != "", do: %{sc.sequence => sc.chunk}, else: %{}

    %{
      status: sc.status,
      last_seq: sc.sequence,
      chunks: chunks,
      closed?: closed?,
      meta: meta
    }
  end

  defp terminal?(:STREAM_STATUS_END), do: true
  defp terminal?(:STREAM_STATUS_CANCEL), do: true
  defp terminal?(:STREAM_STATUS_ERROR), do: true
  defp terminal?(3), do: true
  defp terminal?(4), do: true
  defp terminal?(5), do: true
  defp terminal?(_), do: false
end
