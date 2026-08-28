defmodule IMWeb.Internal.V1.ChannelControllerTest do
  use IMWeb.ConnCase, async: false

  alias IM.AuthFixtures
  alias IM.Services.Channel

  test "缺少 caller 返回 400" do
    conn =
      build_conn()
      |> put_req_header("x-trace-id", "tr-1")
      |> post(~p"/internal/v1/channels/fleet/alert/publish", %{app_key: "x"})

    assert json_response(conn, 400)["msg"] == "missing_caller_service"
  end

  test "internal publish 成功" do
    user = AuthFixtures.create_user!()

    assert {:ok, _} =
             Channel.subscribe(["fleet:alert"], ctx(user), pubsub: true)

    conn =
      build_conn()
      |> put_req_header("x-trace-id", "tr-2")
      |> put_req_header("x-im-caller-service", "ops")
      |> post(~p"/internal/v1/channels/fleet/alert/publish", %{
        app_key: user.app_key,
        content_type: "text/plain",
        payload: "ping"
      })

    assert %{"accepted" => true, "channel_id" => "fleet:alert", "event_id" => eid} =
             json_response(conn, 200)

    assert is_binary(eid)
    assert_receive {:channel_push, _bin}, 500
  end

  defp ctx(user) do
    %IM.Domain.MessageContext{
      app_key: user.app_key,
      user_id: user.user_id,
      device_id: "d",
      session_id: "s",
      trace_id: "t",
      node: node()
    }
  end
end
