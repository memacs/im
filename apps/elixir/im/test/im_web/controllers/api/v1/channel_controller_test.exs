defmodule IMWeb.Api.V1.ChannelControllerTest do
  use IMWeb.ConnCase, async: true

  alias IM.AuthFixtures

  defp auth_conn(token, trace) do
    build_conn()
    |> put_req_header("x-trace-id", trace)
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
  end

  test "PUT/DELETE subscriptions + POST publish" do
    login = AuthFixtures.login!()
    channel_id = "news:rest-#{System.unique_integer([:positive])}"

    sub =
      auth_conn(login.token, "ch-sub")
      |> put(~p"/api/v1/channels/subscriptions", %{channel_ids: [channel_id]})

    assert %{"subscribed" => subscribed} = json_response(sub, 200)
    assert channel_id in subscribed

    pub =
      auth_conn(login.token, "ch-pub")
      |> post(~p"/api/v1/channels/publish", %{
        channel_id: channel_id,
        content_type: "application/json",
        payload: %{"n" => 1},
        client_event_id: "evt-1"
      })

    assert %{"channel_id" => ^channel_id, "event_id" => _, "accepted" => true} =
             json_response(pub, 200)

    unsub =
      auth_conn(login.token, "ch-unsub")
      |> delete(~p"/api/v1/channels/subscriptions", %{channel_ids: [channel_id]})

    assert %{"unsubscribed" => unsubscribed} = json_response(unsub, 200)
    assert channel_id in unsubscribed
  end
end
