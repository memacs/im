defmodule IM.Telemetry.Storage do
  @moduledoc """
  存储耗时 span（`im_storage_duration_ms`）。
  """

  alias IM.Telemetry.Tags

  @doc """
  测量 `fun` 并上报 `operation` / `store`。

  ## 示例

      IM.Telemetry.Storage.span(:query, "message_store", fn -> :ok end)
  """
  @spec span(atom() | String.t(), String.t(), (-> result)) :: result when result: var
  def span(operation, store, fun) when is_function(fun, 0) do
    start = System.monotonic_time()

    try do
      fun.()
    after
      stop(start, operation, store)
    end
  end

  @doc """
  上报已结束的存储 span。

  ## 示例

      IM.Telemetry.Storage.stop(start, :insert, "message_store")
  """
  @spec stop(integer(), atom() | String.t(), String.t()) :: :ok
  def stop(start_native, operation, store)
      when is_integer(start_native) and is_binary(store) do
    :telemetry.execute(
      [:im, :storage, :stop],
      %{duration: System.monotonic_time() - start_native},
      %{
        operation: normalize(operation),
        store: store,
        host: Tags.host()
      }
    )
  end

  defp normalize(op) when is_atom(op), do: Atom.to_string(op)
  defp normalize(op) when is_binary(op), do: op
end
