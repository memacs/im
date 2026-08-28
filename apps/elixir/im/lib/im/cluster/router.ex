defmodule IM.Cluster.Router do
  @moduledoc """
  按 `route_key` 一致性哈希到 Message 节点（P9-06）。

  - `node_role: :all`（默认）：本机处理，单节点/混合部署
  - `node_role: :message`：仅当本机是 owner 时处理
  - `node_role: :access`：WS 接入；业务可 `forward/4` 到 Message 节点
  """

  @doc """
  当前节点角色：`:all` | `:access` | `:message`。

  ## 示例

      :all = IM.Cluster.Router.node_role()
  """
  @spec node_role() :: :all | :access | :message
  def node_role do
    case Application.get_env(:im, :node_role, "all") do
      role when role in [:all, "all", nil] -> :all
      role when role in [:access, "access"] -> :access
      role when role in [:message, "message"] -> :message
      _ -> :all
    end
  end

  @doc """
  Message 角色候选节点（含本机）。可通过 `:message_nodes` 注入测试列表。

  ## 示例

      nodes = IM.Cluster.Router.message_nodes()
  """
  @spec message_nodes() :: [node()]
  def message_nodes do
    case Application.get_env(:im, :message_nodes) do
      list when is_list(list) and list != [] ->
        Enum.uniq(list)

      _ ->
        ([Node.self()] ++ Node.list())
        |> Enum.uniq()
        |> Enum.sort()
    end
  end

  @doc """
  计算 `route_key` 的归属 Message 节点。

  ## 示例

      node = IM.Cluster.Router.owner("g:123")
  """
  @spec owner(String.t() | nil) :: node()
  def owner(route_key) when route_key in [nil, ""], do: Node.self()

  def owner(route_key) when is_binary(route_key) do
    nodes = message_nodes()
    idx = :erlang.phash2(route_key, length(nodes))
    Enum.at(nodes, idx)
  end

  @doc """
  本机是否应直接处理该 `route_key`。
  """
  @spec local?(String.t() | nil) :: boolean()
  def local?(route_key) do
    case node_role() do
      :all -> true
      :message -> owner(route_key) == Node.self()
      :access -> owner(route_key) == Node.self()
    end
  end

  @doc """
  在归属节点执行 MFA；本机则直接 `apply`。

  ## 示例

      IM.Cluster.Router.call("p:a:b", IM.Services.Message, :send, [msg, ctx, []])
  """
  @spec call(String.t() | nil, module(), atom(), list()) :: term()
  def call(route_key, mod, fun, args)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    target = owner(route_key)

    if target == Node.self() do
      apply(mod, fun, args)
    else
      :erpc.call(target, mod, fun, args, rpc_timeout())
    end
  end

  defp rpc_timeout do
    Application.get_env(:im, :cluster_rpc_timeout_ms, 5_000)
  end
end
