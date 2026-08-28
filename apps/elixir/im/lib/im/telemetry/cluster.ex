defmodule IM.Telemetry.Cluster do
  @moduledoc """
  跨节点投递计数（`im_cross_node_dispatch_total`）。
  """

  alias IM.Telemetry.Tags

  @doc """
  记录一次跨节点 dispatch。

  ## 示例

      IM.Telemetry.Cluster.dispatch()
  """
  @spec dispatch(non_neg_integer()) :: :ok
  def dispatch(count \\ 1) when is_integer(count) and count > 0 do
    :telemetry.execute(
      [:im, :cluster, :dispatch],
      %{count: count},
      %{host: Tags.host(), node: Tags.node_name()}
    )
  end
end
