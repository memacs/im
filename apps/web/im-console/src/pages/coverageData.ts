export type CoverageStatus = "可演示" | "待服务端" | "待实现";

export type CoverageItem = {
  id: string;
  domain: string;
  name: string;
  ws?: string;
  rest?: string;
  status: CoverageStatus;
  note?: string;
};

/** 与设计文档 §3.2 对齐；状态随 im-console 实现更新。 */
export const COVERAGE: CoverageItem[] = [
  { id: "login", domain: "连接", name: "登录", rest: "POST /sessions", status: "可演示" },
  { id: "logout", domain: "连接", name: "登出", rest: "DELETE /sessions/current", status: "可演示" },
  { id: "auth", domain: "连接", name: "WS 鉴权", ws: "CMD_AUTH_*", status: "可演示" },
  { id: "reconnect", domain: "连接", name: "刷新后 WS 重连", status: "可演示", note: "Shell 自动 connect+AUTH" },
  { id: "hb", domain: "连接", name: "心跳", ws: "CMD_HEARTBEAT_*", status: "可演示", note: "仅 WS" },
  { id: "kick", domain: "连接", name: "被踢", ws: "CMD_KICK", status: "可演示", note: "仅 WS" },
  { id: "err", domain: "连接", name: "错误", ws: "CMD_ERROR", status: "可演示", note: "Debug 面板" },
  { id: "send", domain: "消息", name: "发消息", ws: "CMD_MSG_SEND", rest: "POST /messages", status: "可演示" },
  { id: "push", domain: "消息", name: "收 PUSH", ws: "CMD_MSG_PUSH*", status: "可演示", note: "含 PUSH_BATCH" },
  { id: "ack", domain: "消息", name: "ACK", ws: "CMD_MSG_ACK_*", rest: "POST /messages/ack", status: "可演示" },
  { id: "ack_batch", domain: "消息", name: "批量 ACK", ws: "CMD_MSG_ACK_BATCH_*", rest: "POST /messages/ack-batch", status: "可演示" },
  { id: "read", domain: "消息", name: "已读", ws: "CMD_MSG_READ", rest: "POST /messages/read", status: "可演示" },
  { id: "conversations", domain: "消息", name: "会话列表/未读", rest: "GET /conversations", status: "可演示" },
  { id: "conv_msgs", domain: "消息", name: "会话历史", rest: "GET /conversations/:id/messages", status: "可演示" },
  { id: "offline", domain: "消息", name: "离线拉取", ws: "CMD_OFFLINE_PULL_*", rest: "GET /messages/inbox", status: "可演示" },
  { id: "recall", domain: "扩展", name: "撤回", ws: "CMD_MSG_RECALL_*", rest: "POST .../recall", status: "可演示" },
  { id: "edit", domain: "扩展", name: "编辑", ws: "CMD_MSG_EDIT_*", rest: "POST .../edit", status: "可演示" },
  { id: "burn", domain: "扩展", name: "阅后即焚", ws: "BURN_PUSH", status: "可演示", note: "Debug PUSH 事件" },
  { id: "pt", domain: "扩展", name: "透传", ws: "CMD_PASSTHROUGH", rest: "POST /passthrough", status: "可演示" },
  { id: "stream", domain: "扩展", name: "MSG_STREAM 落库", ws: "CMD_MSG_SEND", status: "可演示", note: "Chat 四段流式" },
  { id: "group", domain: "群组", name: "CMD_GROUP_* 全套", ws: "600–619", rest: "/groups/*", status: "可演示" },
  { id: "room", domain: "聊天室", name: "CMD_ROOM_* 全套", ws: "700–711", rest: "/rooms/*", status: "可演示" },
  { id: "friend", domain: "好友", name: "CMD_FRIEND_* 全套", ws: "800–822", rest: "/friends/*", status: "可演示" },
  { id: "friend_gate", domain: "好友", name: "须好友才能单聊", status: "可演示", note: "app_configs 配置" },
  { id: "channel", domain: "通道", name: "CMD_CHANNEL_*", ws: "900–906", rest: "/channels/*", status: "可演示" },
  { id: "devices", domain: "设备", name: "push-token / ban", rest: "/devices/*", status: "可演示" },
  { id: "health", domain: "运维", name: "健康检查", rest: "/health/*", status: "可演示", note: "Devices 页" },
  { id: "msgtypes", domain: "消息", name: "全 MsgType 发送", status: "可演示" },
  { id: "dual", domain: "双通道", name: "WS/REST 并列", status: "可演示", note: "各页通道切换" },
  { id: "internal", domain: "内部", name: "/internal/v1", status: "待实现", note: "设计禁止浏览器调用" },
];
