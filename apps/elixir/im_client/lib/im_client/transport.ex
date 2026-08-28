defmodule IM.Client.Transport do
  @moduledoc """
  WebSockex 二进制传输：入站帧转发给 Connection 父进程。

  测试可注入实现相同回调的 FakeTransport。
  """

  use WebSockex

  def start_link(url, parent, _opts \\ []) when is_binary(url) and is_pid(parent) do
    WebSockex.start_link(url, __MODULE__, %{parent: parent})
  end

  def send_binary(pid, data) when is_binary(data) do
    WebSockex.send_frame(pid, {:binary, data})
  end

  def close(pid) do
    Process.exit(pid, :normal)
    :ok
  end

  @impl true
  def handle_frame({:binary, msg}, state) do
    send(state.parent, {:im_client_frame, msg})
    {:ok, state}
  end

  def handle_frame(_other, state), do: {:ok, state}

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    send(state.parent, {:im_client_disconnected, reason})
    {:ok, state}
  end
end
