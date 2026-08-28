defmodule IM.Log.RateLimit do
  @moduledoc """
  高频日志采样：同一 bucket+租户键在窗口内仅放行一条（DD-028 §2.6.7）。
  """

  use GenServer

  @window_ms 60_000

  @doc """
  是否允许输出该采样桶的一条日志。

  ## 示例

      IM.Log.RateLimit.allow?(:auth_failed, app_key: "demo", user_id: "u1")
  """
  @spec allow?(atom(), keyword()) :: boolean()
  def allow?(bucket, fields) when is_atom(bucket) and is_list(fields) do
    key = {bucket, fields[:app_key], fields[:remote_ip] || fields[:user_id] || :global}

    try do
      GenServer.call(__MODULE__, {:allow?, key}, 200)
    catch
      :exit, _ -> true
    end
  end

  @doc false
  @spec reset!() :: :ok
  def reset! do
    GenServer.call(__MODULE__, :reset)
  end

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:allow?, key}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case Map.get(state, key) do
      nil ->
        {:reply, true, Map.put(state, key, now)}

      last when now - last >= @window_ms ->
        {:reply, true, Map.put(state, key, now)}

      _ ->
        {:reply, false, state}
    end
  end

  def handle_call(:reset, _from, _state), do: {:reply, :ok, %{}}
end
