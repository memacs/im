defmodule IM.EventBus.Noop do
  @moduledoc "旁路空实现（默认 / 测试）。"
  @behaviour IM.EventBus

  @impl true
  def publish(_topic, _event, _opts), do: :ok
end
