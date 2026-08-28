defmodule IM.Client.Protocol.SessionTest do
  @moduledoc "连接与会话：CMD_KICK、设备数限制（reject / kick_oldest）。"
  use IM.ClientProtocolCase

  alias IM.AuthFixtures
  alias IM.Client.{Assertions, Connection}
  alias Pb.Im.Protocol.{AuthReq, KickNotify}

  setup do
    previous = Application.get_env(:im, :device_limit)
    on_exit(fn -> restore_device_limit(previous) end)
    :ok
  end

  @tag trace_case: "session_test/内部 kick 在线设备收到 CMD_KICK"
  test "内部 kick 在线设备收到 CMD_KICK" do
    %{client: client, login: login} = connect_authenticated!()

    trace_http!("↑ HTTP POST /internal/v1/users/:id/kick", %{user_id: login.user_id}, %{
      status: 200
    })

    assert %{"ok" => true} = internal_kick_user!(login.user_id, app_key: login.app_key)

    {:ok, packet} = Assertions.await_cmd(client, CmdType.value(:CMD_KICK), 5_000)
    trace!("↓ WS CMD_KICK", packet)
    kick = assert_cmd_resp!(packet, :CMD_KICK, KickNotify)
    assert kick.reason != ""
  end

  @tag trace_case: "session_test/同平台超限 reject 鉴权失败"
  test "同平台超限 reject 鉴权失败" do
    Application.put_env(:im, :device_limit, %{max_per_platform: 1, policy: :reject})

    user = AuthFixtures.create_user!()

    login1 =
      AuthFixtures.login!(
        Map.merge(Map.take(user, [:app_key, :user_id, :password]), %{
          device_id: unique_id("d1"),
          platform: "ios"
        })
      )

    _ = connect_session!(login1)

    login2 =
      AuthFixtures.login!(
        Map.merge(Map.take(user, [:app_key, :user_id, :password]), %{
          device_id: unique_id("d2"),
          platform: "ios"
        })
      )

    {:ok, client2} = Connection.start_link(url: ws_url())
    on_exit(fn -> if Process.alive?(client2), do: Connection.disconnect(client2) end)
    :ok = Connection.connect(client2)

    trace!("↑ WS CMD_AUTH_REQ (第2设备)", %AuthReq{
      app_key: login2.app_key,
      user_id: login2.user_id,
      token: login2.token,
      device_id: login2.device_id,
      platform: login2.platform,
      sdk_ver: "0.1.0"
    })

    assert {:error, %IM.Client.Error{code: :auth_failed, packet: err_packet}} =
             Connection.authenticate(client2, %{
               app_key: login2.app_key,
               user_id: login2.user_id,
               token: login2.token,
               device_id: login2.device_id,
               platform: login2.platform
             })

    trace!("↓ WS CMD_ERROR (设备数超限 reject)", err_packet)
  end

  @tag trace_case: "session_test/同平台超限 kick_oldest 踢掉旧设备"
  test "同平台超限 kick_oldest 踢掉旧设备" do
    Application.put_env(:im, :device_limit, %{
      max_per_platform: 1,
      policy: :kick_oldest_on_platform
    })

    user = AuthFixtures.create_user!()
    base = Map.take(user, [:app_key, :user_id, :password])

    login1 = AuthFixtures.login!(Map.merge(base, %{device_id: unique_id("d1"), platform: "ios"}))
    %{client: old_client} = connect_session!(login1)

    login2 = AuthFixtures.login!(Map.merge(base, %{device_id: unique_id("d2"), platform: "ios"}))

    trace!("↑ WS CMD_AUTH_REQ (新设备)", %AuthReq{
      app_key: login2.app_key,
      user_id: login2.user_id,
      token: login2.token,
      device_id: login2.device_id,
      platform: login2.platform,
      sdk_ver: "0.1.0"
    })

    _ = connect_session!(login2)

    {:ok, packet} = Assertions.await_cmd(old_client, CmdType.value(:CMD_KICK), 5_000)
    trace!("↓ WS CMD_KICK (旧设备)", packet)
    kick = decode_payload!(packet, KickNotify)
    assert kick.reason_code == :KICK_REASON_DEVICE_LIMIT
  end

  defp restore_device_limit(nil), do: Application.delete_env(:im, :device_limit)

  defp restore_device_limit(cfg) when is_map(cfg) do
    Application.put_env(:im, :device_limit, cfg)
  end
end
