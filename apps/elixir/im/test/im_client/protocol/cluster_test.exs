defmodule IM.Client.Protocol.ClusterTest do
  @moduledoc "libcluster 跨节点：UserTracker 定位 + route_key erpc 转发。"
  use IM.ClusterProtocolCase

  alias IM.Client.Connection
  alias IM.Cluster.Router
  alias IM.ClusterPeer

  @tag trace_case: "cluster_test/跨节点 PUSH 单聊"
  test "跨节点 PUSH：收件人在 peer 节点收到单聊" do
    %{a: a, b: b} = connect_pair_on_nodes!()
    peer = ClusterPeer.peer_node()

    ClusterPeer.wait_device_tracked!(
      a.login.app_key,
      b.login.user_id,
      b.login.device_id,
      peer
    )

    trace_as!("A")

    {msg_id, _} =
      send_private!(a.client, a.login.user_id, b.login.user_id, content: "cross-node-push")

    assert msg_id != ""
    trace_as!("B")
    push_packet = Assertions.assert_push(b.client) |> elem(1)
    trace!("↓ WS CMD_MSG_PUSH (peer 节点)", push_packet)
    push = decode_payload!(push_packet, Pb.Im.Protocol.ChatMessage)
    assert push.content == "cross-node-push"
  end

  @tag trace_case: "cluster_test/跨节点 erpc 转发"
  test "跨节点 Message 转发：route_key 归 peer 时 erpc 落库并投递" do
    a = connect_authenticated!()
    b_login = AuthFixtures.login!(app_key: a.login.app_key)

    b =
      connect_authenticated_on_peer!(
        Map.take(b_login, [:app_key, :user_id, :token, :device_id, :platform])
      )

    peer = ClusterPeer.peer_node()
    route_key = ClusterPeer.route_key_for_node(peer)

    assert Router.owner(route_key) == peer
    assert Router.owner(route_key) != ClusterPeer.main_node()

    ClusterPeer.wait_device_tracked!(a.login.app_key, b_login.user_id, b_login.device_id, peer)

    trace_as!("A")

    {:ok, packet} =
      Connection.send_message(a.client, %{
        from: a.login.user_id,
        to: b_login.user_id,
        chat_type: :CHAT_PRIVATE,
        content: "cross-node-erpc",
        route_key: route_key,
        client_msg_id: unique_id("cm")
      })

    trace!("↓ WS CMD_MSG_ACK_DOWN", packet)
    ack = assert_cmd_resp!(packet, :CMD_MSG_ACK_DOWN, Pb.Im.Protocol.MsgAck)
    assert ack.msg_id != ""

    trace_as!("B")
    push_packet = Assertions.assert_push(b.client) |> elem(1)
    trace!("↓ WS CMD_MSG_PUSH (peer)", push_packet)
    push = decode_payload!(push_packet, Pb.Im.Protocol.ChatMessage)
    assert push.content == "cross-node-erpc"
  end

  defp connect_pair_on_nodes! do
    a = connect_authenticated!()
    b = connect_authenticated_on_peer!(app_key: a.login.app_key)
    %{a: a, b: b}
  end
end
