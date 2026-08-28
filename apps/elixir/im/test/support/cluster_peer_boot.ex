defmodule IM.ClusterPeerBoot do
  @moduledoc """
  集群 E2E 专用：在 `:peer` 启动的第二 BEAM 上引导 IM 应用。

  须在 `lib/` 之外——peer 通过 `:rpc.call/4` 远程调用，依赖主节点 `code.add_paths/1`
  同步测试编译产物（含 `test/support`）。
  """

  @secret "test_only_secret_key_base_at_least_64_bytes_long_xxxxxxxxxxxxxxxxxxx"

  @doc false
  @spec boot(node(), node(), non_neg_integer(), keyword()) :: :ok | {:error, term()}
  def boot(main_node, peer_node, port, repo_config) do
    true = Node.connect(main_node)

    for {key, val} <- :rpc.call(main_node, Application, :get_all_env, [:im]) do
      Application.put_env(:im, key, val)
    end

    base = "http://127.0.0.1:#{port}"

    Application.put_env(:im, IM.Repo, repo_config)

    endpoint_cfg =
      Application.get_env(:im, IMWeb.Endpoint, [])
      |> Keyword.merge(
        http: [ip: {127, 0, 0, 1}, port: port],
        secret_key_base: @secret,
        server: true
      )

    Application.put_env(:im, IMWeb.Endpoint, endpoint_cfg)

    Application.put_env(:im, :protocol_e2e_base_url, base)
    Application.put_env(:im, :protocol_e2e_ws_url, base <> "/ws")
    Application.put_env(:im, :message_nodes, Enum.sort([main_node, peer_node]))

    :ok = Application.load(:im)

    case Application.ensure_all_started(:im) do
      {:ok, _} -> :ok
      err -> {:error, {:app, err}}
    end
  end

  @doc """
  在 peer 节点启动 Sandbox owner（`sandbox: false` + shared）。

  跨节点 E2E 无法共享主节点 owner pid，因此 peer 独立 checkout 并提交到 PG，
  与主节点 `sandbox: false` 写入的数据通过数据库可见。
  """
  @spec start_sandbox_owner!() :: pid()
  def start_sandbox_owner! do
    {:ok, pid} =
      Agent.start(fn ->
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(IM.Repo, sandbox: false)
        :ok = Ecto.Adapters.SQL.Sandbox.mode(IM.Repo, {:shared, self()})
      end)

    pid
  end

  @doc false
  @spec stop_sandbox_owner!(pid()) :: :ok
  def stop_sandbox_owner!(pid) when is_pid(pid) do
    Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
  end
end
