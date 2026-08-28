defmodule IM.Health do
  @moduledoc """
  健康检查：区分「存活」（liveness）与「就绪」（readiness）。

  存活只证明 BEAM 与 HTTP 监听正常，**不查数据库**——数据库抖动不应导致整个
  集群被重启。就绪代表本实例确实能对外服务，探针失败时只摘除流量、不重启。

  就绪检查实现通过 `:im, :health_checker` 注入，便于测试替换
  （见仓库根 `docs/design/dependency-abstraction.md`）。
  """

  @default_checker IM.Health.RepoChecker

  defmodule Checker do
    @moduledoc """
    就绪检查行为契约。
    """

    @doc """
    判断本实例是否可以对外提供服务。

    ## 返回值

    - `:ok` — 依赖正常，可接流量
    - `{:error, reason}` — 依赖异常，应从负载均衡摘除
    """
    @callback ready?() :: :ok | {:error, term()}
  end

  @doc """
  存活检查，恒为 `:ok`。

  仅表示进程调度正常、HTTP 监听可响应。

  ## 示例

      iex> IM.Health.live?()
      :ok

  """
  @spec live?() :: :ok
  def live?, do: :ok

  @doc """
  就绪检查，委托给 `:im, :health_checker` 配置的实现。

  ## 示例

      IM.Health.ready?()
      #=> :ok

  ## 返回值

  - `:ok` — 依赖正常
  - `{:error, reason}` — 依赖异常，`reason` 为具体原因
  """
  @spec ready?() :: :ok | {:error, term()}
  def ready? do
    checker = Application.get_env(:im, :health_checker, @default_checker)
    checker.ready?()
  end
end

defmodule IM.Health.RepoChecker do
  @moduledoc """
  默认就绪检查：对主库执行一次 `SELECT 1`。
  """

  @behaviour IM.Health.Checker

  @query_timeout_ms 2_000

  @doc """
  查询主库连通性。

  ## 示例

      iex> IM.Health.RepoChecker.ready?()
      :ok

  ## 返回值

  - `:ok` — 主库可查询
  - `{:error, reason}` — 连接失败或查询超时
  """
  @impl true
  @spec ready?() :: :ok | {:error, term()}
  def ready? do
    case Ecto.Adapters.SQL.query(IM.Repo, "SELECT 1", [], timeout: @query_timeout_ms) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  catch
    :exit, reason -> {:error, reason}
  end
end
