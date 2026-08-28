defmodule IM.ClusterProtocolCase do
  @moduledoc """
  双节点 libcluster E2E 模板（需 `CLUSTER_E2E=1`）。

  - 主节点：现有 `mix test` Endpoint（`protocol_e2e_*`）
  - peer 节点：`:peer` 启动的第二 BEAM，独立 HTTP/WS 端口
  - 共享 PostgreSQL：`sandbox: false` 真实提交，主/peer 各自 Sandbox owner（跨 BEAM 不可共享 pid）
  """

  use ExUnit.CaseTemplate

  alias IM.AuthFixtures
  alias IM.Client.Connection
  alias IM.ClusterPeer

  using do
    quote do
      use ExUnit.Case, async: false

      @moduletag :cluster_e2e

      import IM.ClientProtocolCase,
        except: [connect_authenticated!: 0, connect_authenticated!: 1]

      import IM.ClusterProtocolCase

      alias IM.AuthFixtures
      alias IM.Client.{Assertions, Connection}
      alias IM.ClusterPeer
      alias Pb.Im.Protocol.CmdType
    end
  end

  setup tags do
    cond do
      tags[:cluster_e2e] and not ClusterPeer.enabled?() ->
        {:skip, "set CLUSTER_E2E=1 to run cluster E2E"}

      tags[:cluster_e2e] ->
        owner = Ecto.Adapters.SQL.Sandbox.start_owner!(IM.Repo, shared: true, sandbox: false)
        {:ok, tracker} = Agent.start_link(fn -> [] end)
        Process.put(:cluster_e2e_clients, tracker)

        if IM.ProtocolTraceRegistry.enabled?() do
          unless tags[:trace_case], do: raise("missing @tag trace_case when TRACE_EXPORT=1")
          Process.put(:trace_case_id, tags[:trace_case])
          Process.put(:trace_step, 0)
          Process.put(:trace_actor, "client")
        end

        on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

        on_exit(fn ->
          disconnect_all_clients!(tracker)
          Process.sleep(200)
          ClusterPeer.stop_cluster!()

          if Process.alive?(tracker) do
            Agent.stop(tracker, :normal, 5_000)
          end
        end)

        ClusterPeer.start_cluster!(owner)
        :ok

      true ->
        IM.DataCase.setup_sandbox(%{async: false})
        :ok
    end
  end

  @doc "创建用户、REST 登录并在主节点 WS 鉴权（集群 teardown 统一断开）。"
  @spec connect_authenticated!(map()) :: %{client: pid(), login: map(), auth: map()}
  def connect_authenticated!(attrs \\ %{}) do
    login = AuthFixtures.login!(attrs)

    {:ok, client} = Connection.start_link(url: IM.ClientProtocolCase.ws_url())
    register_client!(client)
    :ok = Connection.connect(client)

    {:ok, auth} =
      Connection.authenticate(client, %{
        app_key: login.app_key,
        user_id: login.user_id,
        token: login.token,
        device_id: login.device_id,
        platform: login.platform
      })

    %{client: client, login: login, auth: auth}
  end

  @doc "在 peer 节点 REST 登录并 WS 鉴权（集群 teardown 统一断开）。"
  @spec connect_authenticated_on_peer!(map()) :: %{client: pid(), login: map(), auth: map()}
  def connect_authenticated_on_peer!(attrs \\ %{}) do
    login = AuthFixtures.login!(attrs)

    {:ok, client} = Connection.start_link(url: ClusterPeer.ws_url())
    register_client!(client)
    :ok = Connection.connect(client)

    {:ok, auth} =
      Connection.authenticate(client, %{
        app_key: login.app_key,
        user_id: login.user_id,
        token: login.token,
        device_id: login.device_id,
        platform: login.platform
      })

    %{client: client, login: login, auth: auth}
  end

  @spec register_client!(pid()) :: :ok
  def register_client!(client) when is_pid(client) do
    Agent.update(client_tracker!(), fn clients -> [client | clients] end)
    :ok
  end

  @spec disconnect_all_clients!(pid() | nil) :: :ok
  def disconnect_all_clients!(tracker \\ nil) do
    tracker = tracker || Process.get(:cluster_e2e_clients)

    if tracker && Process.alive?(tracker) do
      for client <- Agent.get(tracker, & &1), Process.alive?(client) do
        try do
          Connection.disconnect(client)
          Connection.await_disconnected(client, 3_000)
        catch
          :exit, _ -> :ok
        end
      end
    end

    :ok
  end

  defp client_tracker! do
    Process.get(:cluster_e2e_clients) ||
      raise "cluster client tracker not initialized; use IM.ClusterProtocolCase setup"
  end
end
