defmodule IMWeb.ConnCase do
  @moduledoc """
  REST / HTTP 端点测试的用例模板。

  提供已初始化的 `conn`，并在需要数据库的用例中借出 Ecto Sandbox 连接。
  默认 `async: true`；用例可传 `use IMWeb.ConnCase, async: false` 关闭。
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use IMWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import IMWeb.ConnCase

      @endpoint IMWeb.Endpoint
    end
  end

  setup tags do
    IM.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
