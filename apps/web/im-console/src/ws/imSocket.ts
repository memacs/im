import {
  CmdType,
  CodecError,
  decodeAuthResp,
  decodeChatMessage,
  decodeMsgAck,
  decodePacket,
  encodeAuthReq,
  encodeHeartbeatReq,
  encodePacket,
  im,
  setNegotiatedCompression,
} from "../protocol/codec";
import { pushDebug } from "../stores/debugLog";
import { connectionStore } from "../stores/connection";

const CMD_LABEL: Partial<Record<number, string>> = {
  [CmdType.CMD_MSG_PUSH_BATCH]: "MSG_PUSH_BATCH",
  [CmdType.CMD_MSG_RECALL_PUSH]: "MSG_RECALL_PUSH",
  [CmdType.CMD_MSG_EDIT_PUSH]: "MSG_EDIT_PUSH",
  [CmdType.CMD_MSG_BURN_PUSH]: "MSG_BURN_PUSH",
  [CmdType.CMD_FRIEND_REQUEST_PUSH]: "FRIEND_REQUEST_PUSH",
  [CmdType.CMD_FRIEND_ACCEPT_PUSH]: "FRIEND_ACCEPT_PUSH",
  [CmdType.CMD_FRIEND_REJECT_PUSH]: "FRIEND_REJECT_PUSH",
  [CmdType.CMD_FRIEND_DELETE_PUSH]: "FRIEND_DELETE_PUSH",
  [CmdType.CMD_FRIEND_BLOCK_PUSH]: "FRIEND_BLOCK_PUSH",
  [CmdType.CMD_GROUP_DISMISS_PUSH]: "GROUP_DISMISS_PUSH",
  [CmdType.CMD_GROUP_JOIN_PUSH]: "GROUP_JOIN_PUSH",
  [CmdType.CMD_GROUP_LEAVE_PUSH]: "GROUP_LEAVE_PUSH",
  [CmdType.CMD_GROUP_KICK_PUSH]: "GROUP_KICK_PUSH",
  [CmdType.CMD_GROUP_INVITE_PUSH]: "GROUP_INVITE_PUSH",
  [CmdType.CMD_GROUP_SET_ADMIN_PUSH]: "GROUP_SET_ADMIN_PUSH",
  [CmdType.CMD_GROUP_REMOVE_ADMIN_PUSH]: "GROUP_REMOVE_ADMIN_PUSH",
  [CmdType.CMD_GROUP_TRANSFER_PUSH]: "GROUP_TRANSFER_PUSH",
  [CmdType.CMD_GROUP_UPDATE_PUSH]: "GROUP_UPDATE_PUSH",
  [CmdType.CMD_ROOM_DISMISS_PUSH]: "ROOM_DISMISS_PUSH",
  [CmdType.CMD_ROOM_JOIN_PUSH]: "ROOM_JOIN_PUSH",
  [CmdType.CMD_ROOM_LEAVE_PUSH]: "ROOM_LEAVE_PUSH",
  [CmdType.CMD_ROOM_KICK_PUSH]: "ROOM_KICK_PUSH",
  [CmdType.CMD_ROOM_UPDATE_PUSH]: "ROOM_UPDATE_PUSH",
  [CmdType.CMD_CHANNEL_PUSH]: "CHANNEL_PUSH",
  [CmdType.CMD_ERROR]: "ERROR",
};

function notePush(cmd: number, summary: string) {
  connectionStore.addPushEvent({
    cmd,
    kind: CMD_LABEL[cmd] ?? `CMD_${cmd}`,
    summary,
  });
}

export type PacketHandler = (cmd: number, payload: Uint8Array, seq: number, raw: Uint8Array) => void;

type Pending = {
  resolve: (v: { cmd: number; payload: Uint8Array; seq: number }) => void;
  reject: (e: Error) => void;
  timer: ReturnType<typeof setTimeout>;
};

let seq = 0;
let ws: WebSocket | null = null;
let heartbeatTimer: ReturnType<typeof setInterval> | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let intentionalClose = false;
let lastUrl = "";
let lastAuth: {
  appKey: string;
  userId: string;
  token: string;
  deviceId: string;
} | null = null;

const pending = new Map<number, Pending>();
const listeners = new Set<PacketHandler>();

function nextSeq() {
  seq += 1;
  return seq;
}

function clearHeartbeat() {
  if (heartbeatTimer) clearInterval(heartbeatTimer);
  heartbeatTimer = null;
}

function startHeartbeat(intervalSec = 30) {
  clearHeartbeat();
  heartbeatTimer = setInterval(() => {
    void request(CmdType.CMD_HEARTBEAT_REQ, encodeHeartbeatReq()).catch(() => {
      /* 心跳失败由重连处理 */
    });
  }, Math.max(5, intervalSec) * 1000);
}

export function onPacket(fn: PacketHandler) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function sendRaw(cmd: number, payload: Uint8Array, opts?: { cid?: string; routeKey?: string }) {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    throw new Error("ws not open");
  }
  const s = nextSeq();
  const frame = encodePacket({
    cmd,
    seq: s,
    ts: Date.now(),
    cid: opts?.cid ?? "",
    routeKey: opts?.routeKey ?? "",
    payload,
  });
  ws.send(frame);
  pushDebug({ dir: "out", cmd, seq: s, bytes: frame.byteLength });
  return s;
}

export function request(
  cmd: number,
  payload: Uint8Array,
  opts?: { cid?: string; routeKey?: string; timeoutMs?: number },
): Promise<{ cmd: number; payload: Uint8Array; seq: number }> {
  const s = sendRaw(cmd, payload, opts);
  const timeoutMs = opts?.timeoutMs ?? 12_000;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(s);
      reject(new Error(`timeout waiting seq=${s}`));
    }, timeoutMs);
    pending.set(s, { resolve, reject, timer });
  });
}

function handleFrame(data: ArrayBuffer) {
  const buf = new Uint8Array(data);
  try {
    const packet = decodePacket(buf);
    pushDebug({
      dir: "in",
      cmd: packet.cmd,
      seq: packet.seq,
      bytes: buf.byteLength,
    });

    const waiter = pending.get(packet.seq);
    if (waiter && packet.seq !== 0) {
      clearTimeout(waiter.timer);
      pending.delete(packet.seq);
      waiter.resolve({
        cmd: packet.cmd,
        payload: packet.payload,
        seq: packet.seq,
      });
    }

    if (packet.cmd === CmdType.CMD_KICK) {
      connectionStore.setStatus("kicked");
      intentionalClose = true;
      ws?.close();
    }

    if (packet.cmd === CmdType.CMD_MSG_PUSH) {
      try {
        const msg = decodeChatMessage(packet.payload);
        connectionStore.addMessage(msg);
      } catch {
        /* ignore */
      }
    }

    if (packet.cmd === CmdType.CMD_MSG_PUSH_BATCH) {
      try {
        const batch = im.protocol.MsgPushBatch.decode(packet.payload);
        for (const msg of batch.messages ?? []) {
          connectionStore.addMessage(msg);
        }
        notePush(packet.cmd, `batch ${batch.messages?.length ?? 0} msgs`);
      } catch {
        notePush(packet.cmd, "decode failed");
      }
    }

    if (packet.cmd === CmdType.CMD_MSG_RECALL_PUSH) {
      try {
        const r = im.protocol.MsgRecall.decode(packet.payload);
        notePush(packet.cmd, `recall msg=${r.msgId ?? "?"}`);
      } catch {
        notePush(packet.cmd, "decode failed");
      }
    }

    if (packet.cmd === CmdType.CMD_MSG_EDIT_PUSH) {
      try {
        const e = im.protocol.MsgEdit.decode(packet.payload);
        notePush(packet.cmd, `edit msg=${e.msgId ?? "?"}`);
      } catch {
        notePush(packet.cmd, "decode failed");
      }
    }

    if (packet.cmd === CmdType.CMD_MSG_BURN_PUSH) {
      try {
        const b = im.protocol.MsgBurn.decode(packet.payload);
        notePush(packet.cmd, `burn msg=${b.msgId ?? "?"}`);
      } catch {
        notePush(packet.cmd, "decode failed");
      }
    }

    if (packet.cmd === CmdType.CMD_ERROR) {
      try {
        const err = im.protocol.ErrorBody.decode(packet.payload);
        connectionStore.setLastError({
          code: err.code ?? 0,
          msg: err.msg ?? "",
          refCmd: err.refCmd,
          refCid: err.refCid,
        });
        notePush(packet.cmd, `code=${err.code} ${err.msg}`);
      } catch {
        notePush(packet.cmd, "decode failed");
      }
    }

    if (CMD_LABEL[packet.cmd] && packet.cmd !== CmdType.CMD_MSG_PUSH_BATCH &&
        packet.cmd !== CmdType.CMD_MSG_RECALL_PUSH &&
        packet.cmd !== CmdType.CMD_MSG_EDIT_PUSH &&
        packet.cmd !== CmdType.CMD_MSG_BURN_PUSH &&
        packet.cmd !== CmdType.CMD_ERROR &&
        packet.cmd !== CmdType.CMD_CHANNEL_PUSH) {
      notePush(packet.cmd, `${CMD_LABEL[packet.cmd]} received`);
    }

    if (packet.cmd === CmdType.CMD_MSG_ACK_DOWN) {
      try {
        const ack = decodeMsgAck(packet.payload);
        connectionStore.noteAck(ack);
      } catch {
        /* ignore */
      }
    }

    for (const fn of listeners) {
      fn(packet.cmd, packet.payload, packet.seq, buf);
    }
  } catch (e) {
    pushDebug({
      dir: "in",
      cmd: -1,
      seq: 0,
      bytes: buf.byteLength,
      note: e instanceof CodecError ? e.code : String(e),
    });
  }
}

export async function connect(url: string) {
  intentionalClose = false;
  lastUrl = url;
  connectionStore.setStatus("connecting");

  await new Promise<void>((resolve, reject) => {
    ws = new WebSocket(url);
    ws.binaryType = "arraybuffer";
    ws.onopen = () => {
      connectionStore.setStatus("connected");
      resolve();
    };
    ws.onerror = () => reject(new Error("websocket error"));
    ws.onclose = () => {
      clearHeartbeat();
      connectionStore.setStatus(intentionalClose ? connectionStore.snapshot.status : "disconnected");
      if (!intentionalClose && lastUrl && lastAuth) {
        scheduleReconnect();
      }
    };
    ws.onmessage = (ev) => {
      if (ev.data instanceof ArrayBuffer) handleFrame(ev.data);
    };
  });
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  connectionStore.setStatus("reconnecting");
  reconnectTimer = setTimeout(async () => {
    reconnectTimer = null;
    try {
      await connect(lastUrl);
      if (lastAuth) await authenticate(lastAuth);
    } catch {
      scheduleReconnect();
    }
  }, 1500);
}

export async function authenticate(creds: {
  appKey: string;
  userId: string;
  token: string;
  deviceId: string;
}) {
  lastAuth = creds;
  connectionStore.setStatus("authenticating");
  const payload = encodeAuthReq({
    appKey: creds.appKey,
    userId: creds.userId,
    token: creds.token,
    deviceId: creds.deviceId,
    platform: "web",
    sdkVer: "im-console/0.1",
    compressionOffered: [
      im.protocol.PayloadCompression.PAYLOAD_COMPRESSION_NONE,
      im.protocol.PayloadCompression.PAYLOAD_COMPRESSION_GZIP,
    ],
  });
  const resp = await request(CmdType.CMD_AUTH_REQ, payload);
  if (resp.cmd !== CmdType.CMD_AUTH_RESP) {
    connectionStore.setStatus("error");
    throw new Error(`auth failed cmd=${resp.cmd}`);
  }
  const body = decodeAuthResp(resp.payload);
  setNegotiatedCompression(body.payloadCompression ?? 0);
  connectionStore.setStatus("authenticated");
  connectionStore.setAuth(body);
  startHeartbeat(body.heartbeatIntervalSec || 30);
  return body;
}

export function disconnect() {
  intentionalClose = true;
  clearHeartbeat();
  if (reconnectTimer) clearTimeout(reconnectTimer);
  reconnectTimer = null;
  ws?.close();
  ws = null;
  connectionStore.setStatus("disconnected");
}
