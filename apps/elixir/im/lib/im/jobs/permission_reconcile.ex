defmodule IM.Jobs.PermissionReconcile do
  @moduledoc "权限缓存对账 facade。"

  alias IM.Permission.Reconciler

  @doc "同步执行一轮对账（测试 / 运维）。"
  @spec run_once(String.t(), keyword()) :: map()
  def run_once(app_key, opts \\ []), do: Reconciler.run(app_key, opts)

  @doc "入队 Oban。"
  @spec enqueue(String.t(), keyword()) :: :ok
  def enqueue(app_key, opts \\ []) when is_binary(app_key) do
    args = %{
      "app_key" => app_key,
      "sample" => Keyword.get(opts, :sample, 200)
    }

    case args |> IM.Workers.PermissionReconcile.new() |> Oban.insert() do
      {:ok, _} ->
        :ok

      {:error, _} ->
        _ = run_once(app_key, opts)
        :ok
    end
  end
end
