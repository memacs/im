defmodule IM.EventBus.Buffered do
  @moduledoc """
  将 publish 写入 `IM.EventBus.Buffer`（P9-03）。

  不连 Kafka；联调/压测可断言 Buffer 内容。生产后续换 Kafka Producer。
  """

  @behaviour IM.EventBus

  @impl true
  def publish(topic, event, _opts) do
    IM.EventBus.Buffer.enqueue(topic, event)
  end
end
