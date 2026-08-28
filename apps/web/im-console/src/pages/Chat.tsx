import { useSyncExternalStore, useState, useEffect, useCallback } from "react";
import {
  ackBatchRest,
  ackMessageRest,
  editMessageRest,
  fetchConvMessages,
  fetchInbox,
  listConversations,
  markReadRest,
  passthroughRest,
  recallMessageRest,
  sendMessageRest,
} from "../api/client";
import {
  AckStatus,
  ChatType,
  CmdType,
  MsgType,
  encodeMsgAck,
  encodeMsgAckBatch,
  encodeMsgEdit,
  encodeMsgRead,
  encodeMsgRecall,
  encodeMsgSend,
  encodeOfflinePull,
  encodePassthrough,
  encodeStreamContent,
  im,
} from "../protocol/codec";
import { connectionStore } from "../stores/connection";
import { loadSession } from "../stores/session";
import { request } from "../ws/imSocket";

const MSG_TYPES = [
  ["MSG_TEXT", MsgType.MSG_TEXT],
  ["MSG_IMAGE", MsgType.MSG_IMAGE],
  ["MSG_AUDIO", MsgType.MSG_AUDIO],
  ["MSG_VIDEO", MsgType.MSG_VIDEO],
  ["MSG_FILE", MsgType.MSG_FILE],
  ["MSG_LOCATION", MsgType.MSG_LOCATION],
  ["MSG_CUSTOM", MsgType.MSG_CUSTOM],
] as const;

export function ChatPage() {
  const snap = useSyncExternalStore(
    connectionStore.subscribe,
    connectionStore.getSnapshot,
  );
  const session = loadSession();
  const [to, setTo] = useState("bob");
  const [content, setContent] = useState("hello");
  const [msgType, setMsgType] = useState(MsgType.MSG_TEXT);
  const [channel, setChannel] = useState<"ws" | "rest">("ws");
  const [burn, setBurn] = useState(false);
  const [info, setInfo] = useState("");
  const [conversations, setConversations] = useState<
    {
      conv_id: string;
      peer_id?: string;
      unread_count?: number;
      last_msg_preview?: string;
      last_msg_seq?: number;
      last_msg_id?: string;
    }[]
  >([]);
  const [selectedConv, setSelectedConv] = useState("");
  const [inboxPreview, setInboxPreview] = useState("");
  const [totalUnread, setTotalUnread] = useState(0);

  const refreshConversations = useCallback(async () => {
    if (!session?.accessToken) return;
    try {
      const res = await listConversations(session.accessToken, 50);
      setConversations(res.conversations ?? []);
      setTotalUnread(res.total_unread ?? 0);
    } catch (e) {
      setInfo(String(e));
    }
  }, [session?.accessToken]);

  useEffect(() => {
    void refreshConversations();
  }, [refreshConversations, snap.messages.length]);

  async function markReadRestFor(conv: (typeof conversations)[0]) {
    if (!session?.accessToken || !conv.peer_id) return;
    try {
      await markReadRest(session.accessToken, {
        conv_id: conv.conv_id,
        conv_seq: conv.last_msg_seq ?? 0,
        to: conv.peer_id,
        msg_id: conv.last_msg_id ?? "",
      });
      await refreshConversations();
      setInfo(`REST READ ok ${conv.conv_id}`);
    } catch (e) {
      setInfo(String(e));
    }
  }

  async function send() {
    if (!session) return;
    const cid = crypto.randomUUID();
    try {
      if (channel === "rest") {
        const res = await sendMessageRest(session.accessToken, {
          to,
          content,
          chat_type: "private",
          client_msg_id: cid,
        });
        setInfo(`REST ok ${JSON.stringify(res)}`);
        return;
      }
      const payload = encodeMsgSend({
        from: session.userId,
        to,
        chatType: ChatType.CHAT_PRIVATE,
        msgType,
        content: new TextEncoder().encode(content),
        clientMsgId: cid,
        burnAfterRead: burn,
        burnTtlSec: burn ? 30 : 0,
      });
      const resp = await request(CmdType.CMD_MSG_SEND, payload, {
        cid,
        routeKey: to,
      });
      setInfo(`WS resp cmd=${resp.cmd} seq=${resp.seq}`);
      await refreshConversations();
    } catch (e) {
      setInfo(String(e));
    }
  }

  async function ackUp(msg: im.protocol.IChatMessage) {
    if (channel === "rest" && session?.accessToken) {
      await ackMessageRest(session.accessToken, {
        msg_id: msg.msgId ?? "",
        client_msg_id: msg.clientMsgId ?? "",
        conv_seq: Number(msg.convSeq ?? 0),
      });
      setInfo(`REST ACK ${msg.msgId}`);
      return;
    }
    const payload = encodeMsgAck({
      msgId: msg.msgId,
      clientMsgId: msg.clientMsgId,
      status: AckStatus.ACK_CLIENT_RECEIVED,
      convSeq: msg.convSeq,
    });
    await request(CmdType.CMD_MSG_ACK_UP, payload);
  }

  async function ackBatch() {
    if (channel === "rest" && session?.accessToken) {
      const acks = snap.messages.map((m) => ({
        msg_id: m.msgId ?? "",
        client_msg_id: m.clientMsgId ?? "",
        conv_seq: Number(m.convSeq ?? 0),
      }));
      await ackBatchRest(session.accessToken, acks);
      setInfo(`REST ACK_BATCH ${acks.length}`);
      return;
    }
    if (snap.messages.length === 0) return;
    const acks = snap.messages.map((m) => ({
      msgId: m.msgId,
      clientMsgId: m.clientMsgId,
      status: AckStatus.ACK_CLIENT_RECEIVED,
      convSeq: m.convSeq,
    }));
    const payload = encodeMsgAckBatch({ acks });
    await request(CmdType.CMD_MSG_ACK_BATCH_UP, payload);
    setInfo(`ACK_BATCH sent ${acks.length}`);
  }

  async function markRead(msg: im.protocol.IChatMessage) {
    if (!session) return;
    if (channel === "rest") {
      await markReadRest(session.accessToken, {
        conv_id: msg.convId ?? "",
        conv_seq: Number(msg.convSeq ?? 0),
        to: msg.from === session.userId ? (msg.to ?? "") : (msg.from ?? ""),
        msg_id: msg.msgId ?? "",
      });
      setInfo(`REST READ ${msg.msgId}`);
      await refreshConversations();
      return;
    }
    const payload = encodeMsgRead({
      chatType: ChatType.CHAT_PRIVATE,
      from: session.userId,
      to: msg.from === session.userId ? msg.to : msg.from,
      convId: msg.convId,
      msgId: msg.msgId,
      convSeq: msg.convSeq,
      timestamp: Date.now(),
    });
    await request(CmdType.CMD_MSG_READ, payload);
    setInfo(`READ sent ${msg.msgId}`);
    await refreshConversations();
  }

  async function recall(msg: im.protocol.IChatMessage) {
    if (!session) return;
    if (channel === "rest") {
      await recallMessageRest(session.accessToken, msg.msgId ?? "", {
        conv_id: msg.convId ?? "",
      });
      setInfo(`REST recall ${msg.msgId}`);
      return;
    }
    const payload = encodeMsgRecall({
      chatType: msg.chatType,
      from: session.userId,
      to: msg.to,
      convId: msg.convId,
      msgId: msg.msgId,
      timestamp: Date.now(),
    });
    await request(CmdType.CMD_MSG_RECALL_REQ, payload);
  }

  async function edit(msg: im.protocol.IChatMessage) {
    if (!session) return;
    const edited = content + " (edited)";
    if (channel === "rest") {
      await editMessageRest(session.accessToken, msg.msgId ?? "", {
        content: edited,
        conv_id: msg.convId ?? "",
      });
      setInfo(`REST edit ${msg.msgId}`);
      return;
    }
    const payload = encodeMsgEdit({
      chatType: msg.chatType,
      from: session.userId,
      to: msg.to,
      convId: msg.convId,
      msgId: msg.msgId,
      msgType: MsgType.MSG_TEXT,
      content: new TextEncoder().encode(edited),
      timestamp: Date.now(),
    });
    await request(CmdType.CMD_MSG_EDIT_REQ, payload);
  }

  async function offlinePull() {
    if (channel === "rest" && session?.accessToken) {
      const res = await fetchInbox(session.accessToken, snap.inboxSeq, 50);
      setInboxPreview(JSON.stringify(res).slice(0, 800));
      setInfo(`REST inbox ${res.messages?.length ?? 0} msgs`);
      return;
    }
    const payload = encodeOfflinePull({
      cursor: snap.inboxSeq,
      limit: 50,
    });
    const resp = await request(CmdType.CMD_OFFLINE_PULL_REQ, payload);
    setInfo(`OFFLINE_PULL resp cmd=${resp.cmd}`);
  }

  async function pullConvMessages() {
    if (!session?.accessToken || !selectedConv) return;
    const res = await fetchConvMessages(session.accessToken, selectedConv, 0, 20);
    setInboxPreview(JSON.stringify(res).slice(0, 800));
    setInfo(`REST conv ${selectedConv} → ${res.messages?.length ?? 0} msgs`);
  }

  async function passthrough() {
    if (!session) return;
    if (channel === "rest") {
      await passthroughRest(session.accessToken, { to, action: "typing", data: "{}" });
      setInfo("REST passthrough sent");
      return;
    }
    const payload = encodePassthrough({
      to,
      from: session.userId,
      chatType: ChatType.CHAT_PRIVATE,
      action: "typing",
      data: new TextEncoder().encode("{}"),
    });
    await request(CmdType.CMD_PASSTHROUGH, payload);
    setInfo("passthrough sent");
  }

  async function sendStream() {
    if (!session) return;
    const streamId = crypto.randomUUID();
    const text = content || "stream demo";
    const mid = Math.max(1, Math.ceil(text.length / 2));
    const parts: {
      status: im.protocol.StreamStatus;
      sequence: number;
      chunk: string;
    }[] = [
      { status: im.protocol.StreamStatus.STREAM_STATUS_START, sequence: 1, chunk: "" },
      {
        status: im.protocol.StreamStatus.STREAM_STATUS_ONGOING,
        sequence: 2,
        chunk: text.slice(0, mid),
      },
      {
        status: im.protocol.StreamStatus.STREAM_STATUS_ONGOING,
        sequence: 3,
        chunk: text.slice(mid),
      },
      { status: im.protocol.StreamStatus.STREAM_STATUS_END, sequence: 4, chunk: "" },
    ];

    try {
      for (const part of parts) {
        const sc = encodeStreamContent({
          streamId,
          status: part.status,
          sequence: part.sequence,
          chunk: part.chunk,
          contentType: "text/plain",
        });
        const payload = encodeMsgSend({
          from: session.userId,
          to,
          chatType: ChatType.CHAT_PRIVATE,
          msgType: MsgType.MSG_STREAM,
          content: sc,
          clientMsgId: crypto.randomUUID(),
        });
        await request(CmdType.CMD_MSG_SEND, payload, { routeKey: to });
      }
      setInfo(`MSG_STREAM ok streamId=${streamId}`);
    } catch (e) {
      setInfo(String(e));
    }
  }

  return (
    <>
      <div className="panel">
        <div className="row" style={{ justifyContent: "space-between" }}>
          <h2>单聊 / 消息</h2>
          <span className={`badge ${snap.status === "authenticated" ? "ok" : "warn"}`}>
            {snap.status}
          </span>
        </div>
        <div className="row">
          <label>
            to
            <input value={to} onChange={(e) => setTo(e.target.value)} />
          </label>
          <label>
            content
            <input value={content} onChange={(e) => setContent(e.target.value)} />
          </label>
          <label>
            MsgType
            <select
              value={msgType}
              onChange={(e) => setMsgType(Number(e.target.value))}
            >
              {MSG_TYPES.map(([name, v]) => (
                <option key={name} value={v}>
                  {name}
                </option>
              ))}
            </select>
          </label>
          <label>
            通道
            <select
              value={channel}
              onChange={(e) => setChannel(e.target.value as "ws" | "rest")}
            >
              <option value="ws">WS</option>
              <option value="rest">REST</option>
            </select>
          </label>
          <label style={{ flexDirection: "row", alignItems: "center", gap: "0.4rem" }}>
            <input
              type="checkbox"
              checked={burn}
              onChange={(e) => setBurn(e.target.checked)}
            />
            阅后即焚
          </label>
        </div>
        <div className="row" style={{ marginTop: "0.75rem" }}>
          <button onClick={() => void send()}>发送</button>
          <button className="secondary" onClick={() => void offlinePull()}>
            {channel === "rest" ? "REST Inbox" : "OFFLINE_PULL"}
          </button>
          <button className="secondary" onClick={() => void ackBatch()}>
            ACK_BATCH
          </button>
          <button className="secondary" onClick={() => void passthrough()}>
            透传 typing
          </button>
          <button className="secondary" onClick={() => void sendStream()}>
            MSG_STREAM
          </button>
        </div>
        {info ? <p className="mono">{info}</p> : null}
        {snap.lastAck ? (
          <p className="mono">
            last ACK {snap.lastAck.msgId} status={snap.lastAck.status}
          </p>
        ) : null}
      </div>

      <div className="panel">
        <div className="row" style={{ justifyContent: "space-between" }}>
          <h3>会话列表（REST）</h3>
          <span className="badge warn">未读 {totalUnread}</span>
        </div>
        <button className="secondary" type="button" onClick={() => void refreshConversations()}>
          刷新
        </button>
        <div className="msg-list" style={{ marginTop: "0.5rem" }}>
          {conversations.length === 0 ? (
            <div className="mono" style={{ color: "var(--muted)" }}>
              暂无会话
            </div>
          ) : (
            conversations.map((c) => (
              <div className="msg" key={c.conv_id}>
                <div className="mono">
                  {c.peer_id ?? c.conv_id}
                  {(c.unread_count ?? 0) > 0 ? (
                    <span className="badge warn" style={{ marginLeft: "0.5rem" }}>
                      {c.unread_count}
                    </span>
                  ) : null}
                </div>
                <div>{c.last_msg_preview ?? ""}</div>
                <button
                  className="secondary"
                  type="button"
                  style={{ marginTop: "0.35rem" }}
                  onClick={() => void markReadRestFor(c)}
                >
                  REST 已读
                </button>
              </div>
            ))
          )}
        </div>
        {inboxPreview ? (
          <p className="mono" style={{ marginTop: "0.5rem", fontSize: "0.75rem" }}>
            {inboxPreview}
          </p>
        ) : null}
      </div>

      <div className="panel">
        <h3>会话历史（REST）</h3>
        <div className="row">
          <label>
            conv_id
            <input
              value={selectedConv}
              onChange={(e) => setSelectedConv(e.target.value)}
              placeholder="p:alice:bob"
            />
          </label>
          <button className="secondary" type="button" onClick={() => void pullConvMessages()}>
            拉取
          </button>
        </div>
      </div>

      <div className="panel">
        <h3>消息流（PUSH）</h3>
        <div className="msg-list">
          {snap.messages.length === 0 ? (
            <div className="mono" style={{ color: "var(--muted)" }}>
              暂无消息
            </div>
          ) : (
            snap.messages.map((m, i) => (
              <div className="msg" key={`${m.msgId}-${i}`}>
                <div className="mono">
                  {m.from} → {m.to} · {m.msgId} · seq={String(m.convSeq)}
                </div>
                <div>{new TextDecoder().decode(m.content ?? new Uint8Array())}</div>
                <div className="row" style={{ marginTop: "0.35rem" }}>
                  <button className="secondary" onClick={() => void ackUp(m)}>
                    ACK_UP
                  </button>
                  <button className="secondary" onClick={() => void markRead(m)}>
                    READ
                  </button>
                  <button className="secondary" onClick={() => void recall(m)}>
                    撤回
                  </button>
                  <button className="secondary" onClick={() => void edit(m)}>
                    编辑
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </>
  );
}
