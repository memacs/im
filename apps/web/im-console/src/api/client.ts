function traceId() {
  return `web-${crypto.randomUUID().slice(0, 12)}`;
}

export async function apiFetch<T>(
  path: string,
  opts: {
    method?: string;
    token?: string;
    body?: unknown;
  } = {},
): Promise<T> {
  const headers: Record<string, string> = {
    "content-type": "application/json",
    "x-trace-id": traceId(),
  };
  if (opts.token) headers.authorization = `Bearer ${opts.token}`;

  const res = await fetch(path, {
    method: opts.method ?? "GET",
    headers,
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });

  if (res.status === 204) return undefined as T;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(data.msg || `HTTP ${res.status}`);
  }
  return data as T;
}

export type SessionResp = {
  access_token: string;
  connection?: { websocket_urls?: string[] };
};

export function createSession(body: {
  app_key: string;
  user_id: string;
  password: string;
  device_id: string;
  platform?: string;
  sdk_ver?: string;
}) {
  return apiFetch<SessionResp>("/api/v1/sessions", {
    method: "POST",
    body: {
      ...body,
      platform: body.platform ?? "web",
      sdk_ver: body.sdk_ver ?? "im-console/0.2",
    },
  });
}

export function revokeSession(token: string) {
  return apiFetch<void>("/api/v1/sessions/current", {
    method: "DELETE",
    token,
  });
}

// --- Messages ---

export function sendMessageRest(
  token: string,
  body: {
    to: string;
    content: string;
    chat_type?: string;
    client_msg_id?: string;
    msg_type?: string;
    conv_id?: string;
    burn_after_read?: boolean;
    target_users?: string[];
  },
) {
  return apiFetch("/api/v1/messages", { method: "POST", token, body });
}

export function fetchInbox(token: string, cursor = 0, limit = 50) {
  return apiFetch<InboxResp>(
    `/api/v1/messages/inbox?cursor=${cursor}&limit=${limit}`,
    { token },
  );
}

export function fetchConvMessages(
  token: string,
  convId: string,
  cursor = 0,
  limit = 50,
) {
  return apiFetch<InboxResp>(
    `/api/v1/conversations/${encodeURIComponent(convId)}/messages?cursor=${cursor}&limit=${limit}`,
    { token },
  );
}

export type InboxResp = {
  messages?: Record<string, unknown>[];
  next_cursor?: number;
  has_more?: boolean;
};

export function ackMessageRest(
  token: string,
  body: { msg_id: string; client_msg_id?: string; conv_seq?: number },
) {
  return apiFetch("/api/v1/messages/ack", { method: "POST", token, body });
}

export function ackBatchRest(
  token: string,
  acks: { msg_id: string; client_msg_id?: string; conv_seq?: number }[],
) {
  return apiFetch("/api/v1/messages/ack-batch", {
    method: "POST",
    token,
    body: { acks },
  });
}

export function markReadRest(
  token: string,
  body: {
    conv_id: string;
    conv_seq: number;
    to: string;
    msg_id: string;
    chat_type?: string;
  },
) {
  return apiFetch("/api/v1/messages/read", {
    method: "POST",
    token,
    body: { ...body, chat_type: body.chat_type ?? "CHAT_PRIVATE" },
  });
}

export function recallMessageRest(
  token: string,
  msgId: string,
  body: { conv_id?: string; reason?: string } = {},
) {
  return apiFetch(`/api/v1/messages/${encodeURIComponent(msgId)}/recall`, {
    method: "POST",
    token,
    body,
  });
}

export function editMessageRest(
  token: string,
  msgId: string,
  body: { content: string; conv_id?: string },
) {
  return apiFetch(`/api/v1/messages/${encodeURIComponent(msgId)}/edit`, {
    method: "POST",
    token,
    body,
  });
}

export function passthroughRest(
  token: string,
  body: {
    to: string;
    action: string;
    data?: string;
    chat_type?: string;
    conv_id?: string;
    persist?: boolean;
  },
) {
  return apiFetch("/api/v1/passthrough", { method: "POST", token, body });
}

// --- Conversations ---

export type ConversationRow = {
  conv_id: string;
  peer_id?: string;
  unread_count?: number;
  last_msg_preview?: string;
  last_msg_seq?: number;
  last_msg_id?: string;
  chat_type?: number | string;
};

export type ConversationsResp = {
  conversations?: ConversationRow[];
  total_unread?: number;
};

export function listConversations(token: string, limit = 50) {
  return apiFetch<ConversationsResp>(`/api/v1/conversations?limit=${limit}`, {
    token,
  });
}

// --- Friends ---

export function friendAddRest(
  token: string,
  body: { to_user_id: string; message?: string; remark?: string },
) {
  return apiFetch("/api/v1/friends", { method: "POST", token, body });
}

export function friendAcceptRest(
  token: string,
  body: { request_id: string; from_user_id?: string; remark?: string },
) {
  return apiFetch("/api/v1/friends/accept", { method: "POST", token, body });
}

export function friendRejectRest(
  token: string,
  body: { request_id: string },
) {
  return apiFetch("/api/v1/friends/reject", { method: "POST", token, body });
}

export function friendDeleteRest(
  token: string,
  body: { friend_user_id: string },
) {
  return apiFetch("/api/v1/friends", {
    method: "DELETE",
    token,
    body,
  });
}

export function friendBlockRest(token: string, body: { user_id: string }) {
  return apiFetch("/api/v1/friends/block", { method: "POST", token, body });
}

export function friendUnblockRest(token: string, body: { user_id: string }) {
  return apiFetch("/api/v1/friends/unblock", { method: "POST", token, body });
}

export function friendSetRemarkRest(
  token: string,
  body: { friend_user_id: string; remark: string },
) {
  return apiFetch("/api/v1/friends/remark", {
    method: "PUT",
    token,
    body,
  });
}

export function friendListRest(token: string) {
  return apiFetch("/api/v1/friends", { token });
}

export function friendRequestsRest(token: string) {
  return apiFetch("/api/v1/friends/requests", { token });
}

// --- Groups ---

export function createGroupRest(
  token: string,
  body: {
    name: string;
    member_uids?: string[];
    group_id?: string;
    announcement?: string;
    max_members?: number;
  },
) {
  return apiFetch("/api/v1/groups", { method: "POST", token, body });
}

export function groupJoinRest(token: string, groupId: string) {
  return apiFetch(`/api/v1/groups/${encodeURIComponent(groupId)}/join`, {
    method: "POST",
    token,
    body: {},
  });
}

export function groupLeaveRest(token: string, groupId: string) {
  return apiFetch(`/api/v1/groups/${encodeURIComponent(groupId)}/leave`, {
    method: "POST",
    token,
    body: {},
  });
}

export function groupDismissRest(
  token: string,
  groupId: string,
  reason?: string,
) {
  return apiFetch(`/api/v1/groups/${encodeURIComponent(groupId)}/dismiss`, {
    method: "POST",
    token,
    body: reason ? { reason } : {},
  });
}

export function groupKickRest(
  token: string,
  groupId: string,
  body: { member_uids: string[]; reason?: string },
) {
  return apiFetch(`/api/v1/groups/${encodeURIComponent(groupId)}/kick`, {
    method: "POST",
    token,
    body,
  });
}

export function groupInviteRest(
  token: string,
  groupId: string,
  body: { member_uids: string[] },
) {
  return apiFetch(`/api/v1/groups/${encodeURIComponent(groupId)}/invite`, {
    method: "POST",
    token,
    body,
  });
}

export function groupSetAdminRest(
  token: string,
  groupId: string,
  memberUid: string,
) {
  return apiFetch(`/api/v1/groups/${encodeURIComponent(groupId)}/admins`, {
    method: "POST",
    token,
    body: { member_uid: memberUid },
  });
}

export function groupRemoveAdminRest(
  token: string,
  groupId: string,
  memberUid: string,
) {
  return apiFetch(`/api/v1/groups/${encodeURIComponent(groupId)}/admins`, {
    method: "DELETE",
    token,
    body: { member_uid: memberUid },
  });
}

export function groupTransferRest(
  token: string,
  groupId: string,
  newOwnerUid: string,
) {
  return apiFetch(`/api/v1/groups/${encodeURIComponent(groupId)}/transfer`, {
    method: "POST",
    token,
    body: { new_owner_uid: newOwnerUid },
  });
}

export function groupUpdateRest(
  token: string,
  groupId: string,
  body: { name?: string; announcement?: string; max_members?: number },
) {
  return apiFetch(`/api/v1/groups/${encodeURIComponent(groupId)}`, {
    method: "PATCH",
    token,
    body,
  });
}

export function groupMuteRest(
  token: string,
  groupId: string,
  body: { member_uid: string; muted_until: number },
) {
  return apiFetch(`/api/v1/groups/${encodeURIComponent(groupId)}/mute`, {
    method: "POST",
    token,
    body,
  });
}

export function sendGroupMessageRest(
  token: string,
  body: {
    to: string;
    content: string;
    chat_type?: string;
    client_msg_id?: string;
    conv_id?: string;
  },
) {
  return sendMessageRest(token, { ...body, chat_type: "CHAT_GROUP" });
}

// --- Rooms ---

export function createRoomRest(
  token: string,
  body: {
    name: string;
    room_id?: string;
    max_members?: number;
    persist_msg?: boolean;
    msg_ttl_sec?: number;
  },
) {
  return apiFetch("/api/v1/rooms", { method: "POST", token, body });
}

export function roomJoinRest(token: string, roomId: string) {
  return apiFetch(`/api/v1/rooms/${encodeURIComponent(roomId)}/join`, {
    method: "POST",
    token,
    body: {},
  });
}

export function roomLeaveRest(token: string, roomId: string) {
  return apiFetch(`/api/v1/rooms/${encodeURIComponent(roomId)}/leave`, {
    method: "POST",
    token,
    body: {},
  });
}

export function roomDismissRest(
  token: string,
  roomId: string,
  reason?: string,
) {
  return apiFetch(`/api/v1/rooms/${encodeURIComponent(roomId)}/dismiss`, {
    method: "POST",
    token,
    body: reason ? { reason } : {},
  });
}

export function roomKickRest(
  token: string,
  roomId: string,
  body: { member_uids: string[]; reason?: string },
) {
  return apiFetch(`/api/v1/rooms/${encodeURIComponent(roomId)}/kick`, {
    method: "POST",
    token,
    body,
  });
}

export function roomUpdateRest(
  token: string,
  roomId: string,
  body: {
    name?: string;
    max_members?: number;
    persist_msg?: boolean;
    msg_ttl_sec?: number;
  },
) {
  return apiFetch(`/api/v1/rooms/${encodeURIComponent(roomId)}`, {
    method: "PATCH",
    token,
    body,
  });
}

export function sendRoomMessageRest(
  token: string,
  roomId: string,
  body: { content: string; client_msg_id?: string; conv_id?: string },
) {
  return apiFetch(`/api/v1/rooms/${encodeURIComponent(roomId)}/messages`, {
    method: "POST",
    token,
    body,
  });
}

// --- Channels ---

export function subscribeChannelsRest(token: string, channel_ids: string[]) {
  return apiFetch("/api/v1/channels/subscriptions", {
    method: "PUT",
    token,
    body: { channel_ids },
  });
}

export function unsubscribeChannelsRest(token: string, channel_ids: string[]) {
  return apiFetch("/api/v1/channels/subscriptions", {
    method: "DELETE",
    token,
    body: { channel_ids },
  });
}

export function publishChannelRest(
  token: string,
  body: { channel_id: string; content_type?: string; payload: string },
) {
  return apiFetch("/api/v1/channels/publish", {
    method: "POST",
    token,
    body,
  });
}

// --- Devices ---

export function updatePushTokenRest(
  token: string,
  deviceId: string,
  push_token: string,
) {
  return apiFetch(`/api/v1/devices/${encodeURIComponent(deviceId)}/push-token`, {
    method: "PUT",
    token,
    body: { push_token },
  });
}

export function localDataClearedRest(token: string, deviceId: string) {
  return apiFetch<void>(
    `/api/v1/devices/${encodeURIComponent(deviceId)}/local-data-cleared`,
    { method: "POST", token },
  );
}

export function banDeviceRest(
  token: string,
  deviceId: string,
  body: { reason?: string; clear_local_data?: boolean } = {},
) {
  return apiFetch<void>(
    `/api/v1/devices/${encodeURIComponent(deviceId)}/ban`,
    { method: "POST", token, body },
  );
}

// --- Health ---

export function fetchHealthLive() {
  return apiFetch<{ status: string }>("/health/live");
}

export function fetchHealthReady() {
  return apiFetch<{ status: string; database?: string }>("/health/ready");
}
