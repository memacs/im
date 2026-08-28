defmodule IM.Release do
  @moduledoc """
  Release 运行期任务。

  生产 Release 中没有 Mix，`mix ecto.migrate` 不可用，迁移必须经由
  `bin/migrate`（见 `rel/overlays/bin/migrate`）或
  `bin/im eval "IM.Release.migrate()"` 执行。
  """

  @app :im

  @doc """
  执行全部未应用的迁移。

  ## 示例

      # 容器内
      bin/migrate

      # 或
      bin/im eval "IM.Release.migrate()"

  """
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _fun_return, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  将指定仓储回滚到某个版本。

  ## 示例

      bin/im eval "IM.Release.rollback(IM.Repo, 20260803090000)"

  """
  @spec rollback(module(), integer()) :: :ok
  def rollback(repo, version) do
    load_app()

    {:ok, _fun_return, _apps} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))

    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
