defmodule IMWeb.ErrorJSON do
  @moduledoc """
  未被业务捕获的异常与 4xx/5xx 的兜底 JSON 渲染。

  业务错误须走协议统一错误模型（`CMD_ERROR` + `ErrorBody`，
  见仓库根 `docs/design/protocol/protocol.md`），本模块只兜底框架级错误。
  """

  @doc """
  按模板名渲染错误响应体。

  ## 示例

      IMWeb.ErrorJSON.render("404.json", %{})
      #=> %{errors: %{detail: "Not Found"}}

  """
  @spec render(String.t(), map()) :: map()
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
