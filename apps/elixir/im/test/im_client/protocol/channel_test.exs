defmodule IM.Client.Protocol.ChannelTest do
  @moduledoc "应用通道：订阅/取消/客户端上行/内部 publish 下行。"
  use IM.ClientProtocolCase

  alias IM.Client.{Assertions, Connection}
  alias Pb.Im.Protocol.{
    ChannelPublish,
    ChannelPublishAck,
    ChannelPush,
    ChannelSubscribeResp,
    ChannelUnsubscribeReq,
    ChannelUnsubscribeResp
  }

  @tag trace_case: "channel_test/订阅与 publish"
  test "订阅 → 内部 publish → 收 CHANNEL_PUSH → 取消订阅 → 客户端 publish" do
    %{client: client, login: login} = connect_authenticated!()
    channel_id = "news:alerts"

    {:ok, sub_packet} = Connection.subscribe_channels(client, [channel_id])
    trace!("↓ WS CMD_CHANNEL_SUBSCRIBE_RESP", sub_packet)
    sub = assert_cmd_resp!(sub_packet, :CMD_CHANNEL_SUBSCRIBE_RESP, ChannelSubscribeResp)
    assert channel_id in sub.subscribed

    trace_http!("↑ HTTP POST /internal/v1/channels/.../publish", %{channel: channel_id}, %{status: 200})
    internal_channel_publish!("news", "alerts", app_key: login.app_key, payload: %{"n" => 1})

    {:ok, push_packet} = Assertions.await_cmd(client, CmdType.value(:CMD_CHANNEL_PUSH), 5_000)
    trace!("↓ WS CMD_CHANNEL_PUSH", push_packet)
    push = decode_payload!(push_packet, ChannelPush)
    assert push.channel_id == channel_id

    trace!("↑ WS CMD_CHANNEL_UNSUBSCRIBE_REQ", %ChannelUnsubscribeReq{channel_ids: [channel_id]})

    {:ok, unsub_packet} =
      Connection.request(client, :CMD_CHANNEL_UNSUBSCRIBE_REQ, %ChannelUnsubscribeReq{
        channel_ids: [channel_id]
      })

    trace!("↓ WS CMD_CHANNEL_UNSUBSCRIBE_RESP", unsub_packet)
    unsub = assert_cmd_resp!(unsub_packet, :CMD_CHANNEL_UNSUBSCRIBE_RESP, ChannelUnsubscribeResp)
    assert channel_id in unsub.unsubscribed

    trace!("↑ WS CMD_CHANNEL_PUBLISH", %ChannelPublish{
      channel_id: channel_id,
      content_type: "application/json",
      payload: ~s({"client":true})
    })

    {:ok, pub_packet} =
      Connection.request(client, :CMD_CHANNEL_PUBLISH, %ChannelPublish{
        channel_id: channel_id,
        content_type: "application/json",
        payload: ~s({"client":true})
      })

    trace!("↓ WS CMD_CHANNEL_PUBLISH_ACK", pub_packet)
    ack = assert_cmd_resp!(pub_packet, :CMD_CHANNEL_PUBLISH_ACK, ChannelPublishAck)
    assert ack.channel_id == channel_id
  end
end
