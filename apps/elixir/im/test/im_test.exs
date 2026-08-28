defmodule IMTest do
  use ExUnit.Case
  doctest IM

  test "返回 :world" do
    assert IM.hello() == :world
  end
end
