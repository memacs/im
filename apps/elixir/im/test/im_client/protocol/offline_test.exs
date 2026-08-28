defmodule IM.Client.Protocol.OfflineTest do
  @moduledoc "离线拉取：CMD_OFFLINE_PULL。"
  use IM.ClientProtocolCase

  alias IM.Client.Connection
  alias Pb.Im.Protocol.{OfflinePullReq, OfflinePullResp}

  @tag trace_case: "offline_test/离线消息可通过 CMD_OFFLINE_PULL 拉取"
  test "离线消息可通过 CMD_OFFLINE_PULL 拉取" do
    a = connect_authenticated!()
    login_b = AuthFixtures.login!(app_key: a.login.app_key)

    trace_as!("A")
    {msg_id, conv_id} =
      send_private!(a.client, a.login.user_id, login_b.user_id, content: "offline-msg")

    b = connect_authenticated!(app_key: a.login.app_key, user_id: login_b.user_id)
    trace_as!("B")

    trace!("↑ WS CMD_OFFLINE_PULL_REQ", %OfflinePullReq{conv_id: conv_id, cursor: 0, limit: 50})

    {:ok, packet} = Connection.offline_pull(b.client, %{conv_id: conv_id, cursor: 0, limit: 50})
    trace!("↓ WS CMD_OFFLINE_PULL_RESP", packet)
    resp = assert_cmd_resp!(packet, :CMD_OFFLINE_PULL_RESP, OfflinePullResp)
    assert Enum.any?(resp.messages, &(&1.msg_id == msg_id and &1.content == "offline-msg"))
  end
end
