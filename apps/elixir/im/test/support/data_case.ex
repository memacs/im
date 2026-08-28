defmodule IM.DataCase do
  @moduledoc """
  需要访问数据库的测试用例模板。

  每个用例在 Ecto Sandbox 事务中运行，结束后回滚，因此默认可 `async: true`。
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import IM.DataCase

      alias IM.Repo
    end
  end

  setup tags do
    setup_sandbox(tags)
    :ok
  end

  @doc """
  按用例的 `async` 标记借出并配置 Sandbox 连接。

  ## 示例

      setup tags do
        IM.DataCase.setup_sandbox(tags)
        :ok
      end

  """
  @spec setup_sandbox(map()) :: :ok
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(IM.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
