defmodule IM.Client do
  @moduledoc """
  IM 协议客户端门面：建连、鉴权、心跳、消息与业务命令封装。

  实现细节见 `IM.Client.Connection` / `IM.Client.REST`。
  测试辅助（`IM.Client.Assertions`、`IM.Client.Scenario`）见 `test/support/`。
  """

  alias IM.Client.Connection

  @type client :: pid()

  defdelegate start_link(opts), to: Connection
  defdelegate connect(client), to: Connection
  defdelegate authenticate(client, attrs), to: Connection
  defdelegate heartbeat(client), to: Connection
  defdelegate heartbeat(client, opts), to: Connection
  defdelegate send_message(client, attrs), to: Connection
  defdelegate subscribe_channels(client, channel_ids), to: Connection
  defdelegate request(client, cmd, payload), to: Connection
  defdelegate request(client, cmd, payload, opts), to: Connection
  defdelegate ack_client_received(client, attrs), to: Connection
  defdelegate ack_batch(client, acks), to: Connection
  defdelegate msg_read(client, attrs), to: Connection
  defdelegate offline_pull(client), to: Connection
  defdelegate offline_pull(client, attrs), to: Connection
  defdelegate recall_message(client, attrs), to: Connection
  defdelegate edit_message(client, attrs), to: Connection
  defdelegate passthrough(client, attrs), to: Connection
  defdelegate create_group(client, attrs), to: Connection
  defdelegate join_group(client, group_id), to: Connection
  defdelegate leave_group(client, group_id), to: Connection
  defdelegate dismiss_group(client, group_id), to: Connection
  defdelegate kick_group_members(client, attrs), to: Connection
  defdelegate invite_group_members(client, attrs), to: Connection
  defdelegate set_group_admin(client, attrs), to: Connection
  defdelegate remove_group_admin(client, attrs), to: Connection
  defdelegate create_room(client, attrs), to: Connection
  defdelegate join_room(client, room_id), to: Connection
  defdelegate leave_room(client, room_id), to: Connection
  defdelegate add_friend(client, attrs), to: Connection
  defdelegate accept_friend(client, attrs), to: Connection
  defdelegate reject_friend(client, attrs), to: Connection
  defdelegate delete_friend(client, attrs), to: Connection
  defdelegate block_friend(client, attrs), to: Connection
  defdelegate unblock_friend(client, attrs), to: Connection
  defdelegate list_friends(client), to: Connection
  defdelegate disconnect(client), to: Connection
  defdelegate await(client, matcher), to: Connection
  defdelegate await(client, matcher, timeout), to: Connection
  defdelegate status(client), to: Connection
end
