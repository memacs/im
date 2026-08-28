defmodule IM.Client.FakeTransport do
  @moduledoc false

  use GenServer

  def start_link(_url, parent, _opts \\ []) do
    GenServer.start_link(__MODULE__, parent)
  end

  def send_binary(pid, data), do: GenServer.call(pid, {:send, data})

  def close(pid) do
    GenServer.stop(pid, :normal)
    :ok
  end

  @doc "测试辅助：向 Connection 注入一帧。"
  def inject(pid, binary), do: GenServer.cast(pid, {:inject, binary})

  @doc "取出 Connection 发往传输层的最后一帧。"
  def last_sent(pid), do: GenServer.call(pid, :last_sent)

  @impl true
  def init(parent), do: {:ok, %{parent: parent, last_sent: nil}}

  @impl true
  def handle_call({:send, data}, _from, state) do
    {:reply, :ok, %{state | last_sent: data}}
  end

  def handle_call(:last_sent, _from, state), do: {:reply, state.last_sent, state}

  @impl true
  def handle_cast({:inject, binary}, state) do
    send(state.parent, {:im_client_frame, binary})
    {:noreply, state}
  end
end
