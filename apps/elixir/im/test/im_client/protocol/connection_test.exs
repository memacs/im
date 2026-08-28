defmodule IM.Client.Protocol.ConnectionTest do
  @moduledoc "连接与会话：REST 登录、WS AUTH、心跳、登出、/metrics。"
  use IM.ClientProtocolCase

  alias IM.Client.{Connection, REST}
  alias Pb.Im.Protocol.{AuthReq, HeartbeatReq, HeartbeatResp}

  @tag trace_case: "connection_test/REST 登录 + WS AUTH + 心跳"
  test "REST 登录 + WS AUTH + 心跳" do
    %{user_id: user_id, password: password, app_key: app_key} = AuthFixtures.create_user!()
    device_id = unique_id("d")

    assert {:ok, session} =
             REST.create_session(base_url(), %{
               app_key: app_key,
               user_id: user_id,
               password: password,
               device_id: device_id
             })

    trace_http!(
      "↑ HTTP POST /api/v1/sessions",
      %{
        app_key: app_key,
        user_id: user_id,
        device_id: device_id
      },
      %{status: 200, body: session.raw}
    )

    assert [ws | _] = session.websocket_urls
    {:ok, client} = Connection.start_link(url: ws)
    on_exit(fn -> if Process.alive?(client), do: Connection.disconnect(client) end)
    :ok = Connection.connect(client)

    trace!("↑ WS CMD_AUTH_REQ", %AuthReq{
      app_key: app_key,
      user_id: user_id,
      token: session.access_token,
      device_id: device_id,
      platform: "ios",
      sdk_ver: "0.1.0"
    })

    {:ok, auth} =
      Connection.authenticate(client, %{
        app_key: app_key,
        user_id: user_id,
        token: session.access_token,
        device_id: device_id
      })

    trace!("↓ WS CMD_AUTH_RESP", auth.packet)

    {:ok, hb_packet} = Connection.heartbeat(client)
    trace!("↑ WS CMD_HEARTBEAT_REQ", %HeartbeatReq{client_time: System.system_time(:millisecond)})
    resp = assert_cmd_resp!(hb_packet, :CMD_HEARTBEAT_RESP, HeartbeatResp)
    trace!("↓ WS CMD_HEARTBEAT_RESP", hb_packet)
    assert resp.server_time > 0
  end

  @tag trace_case: "connection_test/登出 DELETE sessions"
  test "connect_authenticated! 辅助与 DELETE sessions/current" do
    %{login: login} = connect_authenticated!()

    trace_http!("↑ WS 已鉴权（见 connect_authenticated!）", %{user_id: login.user_id}, %{
      status: "authenticated"
    })

    logout!(login.token)
    trace_http!("↑ HTTP DELETE /api/v1/sessions/current", %{token: "Bearer …"}, %{status: 204})
    assert {:error, _} = IM.Auth.verify_token(login.token)
  end

  @tag trace_case: "connection_test/GET metrics"
  test "GET /metrics 可访问" do
    url = base_url() <> "/metrics"

    assert {:ok, %Req.Response{status: 200, body: body}} =
             Req.get(url, receive_timeout: 10_000)

    trace_http!("↑ HTTP GET /metrics", %{}, %{
      status: 200,
      body: String.slice(body, 0, 200) <> "…"
    })

    assert body =~ "im_"
  end
end
