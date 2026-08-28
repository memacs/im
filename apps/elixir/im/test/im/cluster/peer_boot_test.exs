defmodule IM.ClusterPeerBootTest do
  @moduledoc false
  use ExUnit.Case, async: false

  @tag :cluster_e2e
  test "peer boot smoke" do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(IM.Repo, shared: true, sandbox: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    main =
      case Node.self() do
        :nonode@nohost ->
          {:ok, _} = :net_kernel.start([:"im_test@127.0.0.1", :longnames])
          :"im_test@127.0.0.1"

        n ->
          n
      end

    cookie = Node.get_cookie()

    {:ok, pid, peer} =
      :peer.start_link(%{name: :im_peer, host: ~c"127.0.0.1", cookie: cookie})

    on_exit(fn ->
      try do
        :peer.stop(pid)
      catch
        :exit, _ -> :ok
      end
    end)

    assert wait(fn -> peer in Node.list() end)

    :ok = :rpc.call(peer, :code, :add_paths, [:code.get_path()])

    result =
      :rpc.call(
        peer,
        IM.ClusterPeerBoot,
        :boot,
        [
          main,
          peer,
          4102,
          Application.fetch_env!(:im, IM.Repo)
        ],
        120_000
      )

    assert result == :ok, "boot returned #{inspect(result)}"

    peer_owner = :rpc.call(peer, IM.ClusterPeerBoot, :start_sandbox_owner!, [])
    assert is_pid(peer_owner)
    on_exit(fn -> :rpc.call(peer, IM.ClusterPeerBoot, :stop_sandbox_owner!, [peer_owner]) end)

    app_key = "peer-boot-#{System.unique_integer([:positive])}"
    user_id = "u-#{System.unique_integer([:positive])}"

    {:ok, _} =
      IM.Stores.UserStore.ensure(%{
        app_key: app_key,
        user_id: user_id,
        password_hash: IM.Auth.Password.hash("secret", app_key, user_id)
      })

    assert :rpc.call(peer, IM.Repo, :get_by, [
             IM.Schemas.User,
             [app_key: app_key, user_id: user_id]
           ])
  end

  defp wait(fun, n \\ 50) do
    if fun.() do
      true
    else
      if n > 0 do
        # 轮询 peer 节点进程就绪
        Process.sleep(50)
        wait(fun, n - 1)
      else
        false
      end
    end
  end
end
