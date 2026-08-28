defmodule IM.Client.Protocol.AuthGuardTest do
  @moduledoc "鉴权守卫：未鉴权非法命令静默关闭、鉴权超时、重复 AUTH、无效 token。"
  use IM.ClientProtocolCase

  alias IM.Client.Connection
  alias Pb.Im.Protocol.{AuthReq, ChatMessage, ErrorBody, HeartbeatReq, KickNotify, MsgSendReq}

  setup do
    previous = Application.get_env(:im, :auth_timeout_ms, 10_000)
    on_exit(fn -> Application.put_env(:im, :auth_timeout_ms, previous) end)
    :ok
  end

  @tag trace_case: "auth_guard_test/未鉴权发心跳静默关闭"
  test "未鉴权发心跳静默关闭" do
    client = connect_ws_only!()
    trace!("↑ WS CMD_HEARTBEAT_REQ (未鉴权)", %HeartbeatReq{client_time: 1})

    assert :ok =
             Connection.send_raw(client,
               cmd: :CMD_HEARTBEAT_REQ,
               payload: %HeartbeatReq{client_time: 1}
             )

    assert_silent_close!(client)
    trace_event!("↓ WS 连接静默关闭", %{event: "silent_close", detail: "未鉴权发心跳，无 CMD_ERROR"})
  end

  @tag trace_case: "auth_guard_test/未鉴权发 MSG_SEND 静默关闭"
  test "未鉴权发 MSG_SEND 静默关闭" do
    client = connect_ws_only!()
    cid = unique_id("cm")

    trace!("↑ WS CMD_MSG_SEND (未鉴权)", %MsgSendReq{
      message: %ChatMessage{
        from: "u1",
        to: "u2",
        chat_type: :CHAT_PRIVATE,
        msg_type: :MSG_TEXT,
        content: "illegal",
        client_msg_id: cid
      }
    })

    assert :ok =
             Connection.send_raw(client,
               cmd: :CMD_MSG_SEND,
               payload: %MsgSendReq{
                 message: %ChatMessage{
                   from: "u1",
                   to: "u2",
                   chat_type: :CHAT_PRIVATE,
                   msg_type: :MSG_TEXT,
                   content: "illegal",
                   client_msg_id: cid
                 }
               }
             )

    assert_silent_close!(client)
    trace_event!("↓ WS 连接静默关闭", %{event: "silent_close", detail: "未鉴权发 MSG_SEND"})
  end

  @tag trace_case: "auth_guard_test/鉴权超时静默关闭"
  test "鉴权超时静默关闭" do
    Application.put_env(:im, :auth_timeout_ms, 300)
    client = connect_ws_only!()
    assert_silent_close!(client, 3_000)
    trace_event!("↓ WS 连接静默关闭", %{event: "silent_close", detail: "AUTH 超时未发送 CMD_AUTH_REQ"})
  end

  @tag trace_case: "auth_guard_test/已鉴权再发 AUTH"
  test "已鉴权再发 AUTH 返回 CMD_ERROR 并关闭" do
    %{client: client, login: login} = connect_authenticated!()

    trace!("↑ WS CMD_AUTH_REQ (重复)", %AuthReq{
      app_key: login.app_key,
      user_id: login.user_id,
      token: login.token,
      device_id: login.device_id,
      platform: login.platform,
      sdk_ver: "1.0.0"
    })

    assert :ok =
             Connection.send_raw(client,
               cmd: :CMD_AUTH_REQ,
               payload: %AuthReq{
                 app_key: login.app_key,
                 user_id: login.user_id,
                 token: login.token,
                 device_id: login.device_id,
                 platform: login.platform,
                 sdk_ver: "1.0.0"
               }
             )

    assert {:ok, packet} = Connection.await(client, [cmd: Pb.Im.Protocol.CmdType.value(:CMD_ERROR)], 3_000)
    trace!("↓ WS CMD_ERROR", packet)
    assert_cmd_error!(packet, :CODE_UNAUTHORIZED)
    assert :ok = Connection.await_disconnected(client, 3_000)
  end

  @tag trace_case: "auth_guard_test/无效 token"
  test "无效 token 返回 CMD_ERROR(ref_cmd=AUTH) 并关闭" do
    user = AuthFixtures.create_user!()
    client = connect_ws_only!()
    trace_auth_rejected!(client, user.app_key, user.user_id, "not-a-valid-token", unique_id("d"))
  end

  @tag trace_case: "auth_guard_test/已吊销 token"
  test "已吊销 token 返回 CMD_ERROR 并关闭" do
    login = AuthFixtures.login!()
    logout!(login.token)
    client = connect_ws_only!()
    trace_auth_rejected!(client, login.app_key, login.user_id, login.token, login.device_id)
  end

  @tag trace_case: "auth_guard_test/token 与 user_id 不匹配"
  test "token 与 user_id 不匹配返回 CMD_ERROR 并关闭" do
    login = AuthFixtures.login!()
    client = connect_ws_only!()

    trace_auth_rejected!(
      client,
      login.app_key,
      "wrong-user-#{System.unique_integer([:positive])}",
      login.token,
      login.device_id
    )
  end

  @tag trace_case: "auth_guard_test/token 与 device_id 不匹配"
  test "token 与 device_id 不匹配返回 CMD_ERROR 并关闭" do
    login = AuthFixtures.login!()
    client = connect_ws_only!()
    trace_auth_rejected!(client, login.app_key, login.user_id, login.token, unique_id("wrong-device"))
  end

  @tag trace_case: "auth_guard_test/过期 token"
  test "过期 token 返回 CMD_ERROR 并关闭" do
    login = AuthFixtures.login!()
    expire_token!(login.token)
    client = connect_ws_only!()
    trace_auth_rejected!(client, login.app_key, login.user_id, login.token, login.device_id)
  end

  @tag trace_case: "auth_guard_test/封禁设备 AUTH"
  test "封禁设备 AUTH 返回 CMD_ERROR 并关闭" do
    login = AuthFixtures.login!()

    assert {:ok, _} =
             IM.Stores.UserDeviceStore.ban(login.app_key, login.user_id, login.device_id, "e2e")

    :ok = IM.Permission.DeviceBanCache.put(login.app_key, login.user_id, login.device_id)
    client = connect_ws_only!()

    err =
      trace_auth_rejected!(client, login.app_key, login.user_id, login.token, login.device_id)

    assert err.msg =~ "device_banned"
  end

  @tag trace_case: "auth_guard_test/连接中 token 过期 CMD_KICK"
  test "连接中 token 过期收到 CMD_KICK token_expired" do
    login = AuthFixtures.login!()

    soon =
      DateTime.utc_now()
      |> DateTime.add(300, :millisecond)
      |> DateTime.truncate(:microsecond)

    set_token_expires_at!(login.token, soon)

    client = connect_ws_only!()

    assert {:ok, _} =
             Connection.authenticate(client, %{
               app_key: login.app_key,
               user_id: login.user_id,
               token: login.token,
               device_id: login.device_id,
               platform: "ios"
             })

    {:ok, packet} = Assertions.await_cmd(client, CmdType.value(:CMD_KICK), 5_000)
    trace!("↓ WS CMD_KICK (token_expired)", packet)
    kick = assert_cmd_resp!(packet, :CMD_KICK, KickNotify)
    assert kick.reason == "token_expired" or kick.reason_code == :KICK_REASON_TOKEN_EXPIRED
    assert :ok = Connection.await_disconnected(client, 3_000)
  end

  defp trace_auth_rejected!(client, app_key, user_id, token, device_id) do
    trace!("↑ WS CMD_AUTH_REQ", %AuthReq{
      app_key: app_key,
      user_id: user_id,
      token: token,
      device_id: device_id,
      platform: "ios",
      sdk_ver: "0.1.0"
    })

    assert {:error, %IM.Client.Error{packet: err_packet}} =
             Connection.authenticate(client, %{
               app_key: app_key,
               user_id: user_id,
               token: token,
               device_id: device_id,
               platform: "ios"
             })

    trace!("↓ WS CMD_ERROR", err_packet)
    err = assert_cmd_error!(err_packet, :CODE_UNAUTHORIZED)
    assert err.ref_cmd == Pb.Im.Protocol.CmdType.value(:CMD_AUTH_REQ)
    assert :ok = Connection.await_disconnected(client, 3_000)
    err
  end
end
