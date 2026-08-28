defmodule IMWeb.ErrorJSONTest do
  use ExUnit.Case, async: true

  alias IMWeb.ErrorJSON

  test "render/2 返回 Phoenix 状态文案" do
    assert ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Not Found"}
           }
  end
end
