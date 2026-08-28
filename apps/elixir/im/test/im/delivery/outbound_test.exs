defmodule IM.Delivery.OutboundTest do
  use ExUnit.Case, async: true

  alias IM.Delivery.Outbound

  test "按 priority 高到低，同级按 inbox_seq" do
    items = [
      %{priority: :low, inbox_seq: 3, id: :a},
      %{priority: :high, inbox_seq: 2, id: :b},
      %{priority: :high, inbox_seq: 1, id: :c},
      %{priority: :normal, inbox_seq: 4, id: :d}
    ]

    assert Enum.map(Outbound.sort_by_priority(items), & &1.id) == [:c, :b, :d, :a]
  end
end
