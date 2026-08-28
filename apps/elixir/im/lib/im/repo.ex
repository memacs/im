defmodule IM.Repo do
  @moduledoc """
  PostgreSQL 主库仓储。

  表结构与索引设计见仓库根 `docs/design/database/database-design.md`；
  连接参数在 `config/runtime.exs` 由 `DATABASE_URL` 注入。
  """

  use Ecto.Repo,
    otp_app: :im,
    adapter: Ecto.Adapters.Postgres
end
