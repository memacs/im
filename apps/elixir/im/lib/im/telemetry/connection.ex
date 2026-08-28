defmodule IM.Telemetry.Connection do
  @moduledoc """
  连接建立与鉴权结果计数（DD-028 §2.3.3）。
  """

  alias IM.Telemetry.Tags

  @doc """
  累计建连（含未鉴权）。

  ## 示例

      IM.Telemetry.Connection.opened()
  """
  @spec opened() :: :ok
  def opened do
    :telemetry.execute(
      [:im, :connection, :opened],
      %{count: 1},
      %{host: Tags.host(), node: Tags.node_name()}
    )
  end

  @doc """
  鉴权结果。

  ## 示例

      IM.Telemetry.Connection.auth(:success)
  """
  @spec auth(:success | :failure) :: :ok
  def auth(result) when result in [:success, :failure] do
    :telemetry.execute(
      [:im, :auth, :result],
      %{count: 1},
      %{result: result, host: Tags.host()}
    )
  end
end
