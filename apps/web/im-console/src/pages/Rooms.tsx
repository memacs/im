import { useState } from "react";
import {
  createRoomRest,
  roomDismissRest,
  roomJoinRest,
  roomKickRest,
  roomLeaveRest,
  roomUpdateRest,
  sendRoomMessageRest,
} from "../api/client";
import {
  ChatType,
  CmdType,
  MsgType,
  encodeMsgSend,
  encodeRoomCreate,
  encodeRoomOperate,
  im,
} from "../protocol/codec";
import { loadSession } from "../stores/session";
import { request } from "../ws/imSocket";

type Channel = "ws" | "rest";

function parseMembers(raw: string) {
  return raw.split(/[,\s]+/).filter(Boolean);
}

export function RoomsPage() {
  const session = loadSession();
  const [name, setName] = useState("demo-room");
  const [roomId, setRoomId] = useState("");
  const [targetUid, setTargetUid] = useState("bob");
  const [maxMembers, setMaxMembers] = useState("500");
  const [channel, setChannel] = useState<Channel>("ws");
  const [info, setInfo] = useState("");

  const token = session?.accessToken ?? "";

  async function run(label: string, fn: () => Promise<unknown>) {
    try {
      const res = await fn();
      const text =
        res === undefined ? "ok" : typeof res === "object" ? JSON.stringify(res) : String(res);
      setInfo(`${label}: ${text}`);
      if (typeof res === "object" && res && "room_id" in res) {
        setRoomId(String((res as { room_id: string }).room_id));
      }
    } catch (e) {
      setInfo(`${label}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  async function create() {
    if (channel === "rest") {
      await run("create", () =>
        createRoomRest(token, { name, max_members: Number(maxMembers) || 500 }),
      );
      return;
    }
    await run("create", async () => {
      const payload = encodeRoomCreate({ name, maxMembers: Number(maxMembers) || 500 });
      const resp = await request(CmdType.CMD_ROOM_CREATE_REQ, payload);
      const body = im.protocol.RoomCreateResp.decode(resp.payload);
      return { room_id: body.roomId, name: body.name };
    });
  }

  async function join() {
    if (channel === "rest") {
      await run("join", () => roomJoinRest(token, roomId));
      return;
    }
    await run("join", () =>
      request(CmdType.CMD_ROOM_JOIN_REQ, encodeRoomOperate({ roomId })),
    );
  }

  async function leave() {
    if (channel === "rest") {
      await run("leave", () => roomLeaveRest(token, roomId));
      return;
    }
    await run("leave", () =>
      request(CmdType.CMD_ROOM_LEAVE_REQ, encodeRoomOperate({ roomId })),
    );
  }

  async function dismiss() {
    if (channel === "rest") {
      await run("dismiss", () => roomDismissRest(token, roomId));
      return;
    }
    await run("dismiss", () =>
      request(CmdType.CMD_ROOM_DISMISS_REQ, encodeRoomOperate({ roomId })),
    );
  }

  async function kick() {
    const uids = parseMembers(targetUid);
    if (channel === "rest") {
      await run("kick", () => roomKickRest(token, roomId, { member_uids: uids }));
      return;
    }
    const payload = im.protocol.RoomKickReq.encode(
      im.protocol.RoomKickReq.create({ roomId, memberUids: uids }),
    ).finish();
    await run("kick", () => request(CmdType.CMD_ROOM_KICK_REQ, payload));
  }

  async function update() {
    if (channel === "rest") {
      await run("update", () =>
        roomUpdateRest(token, roomId, {
          name,
          max_members: Number(maxMembers) || undefined,
        }),
      );
      return;
    }
    const payload = im.protocol.RoomUpdateReq.encode(
      im.protocol.RoomUpdateReq.create({
        roomId,
        name,
        maxMembers: Number(maxMembers) || 0,
      }),
    ).finish();
    await run("update", () => request(CmdType.CMD_ROOM_UPDATE_REQ, payload));
  }

  async function broadcast() {
    if (!session) return;
    const cid = crypto.randomUUID();
    if (channel === "rest") {
      await run("room_msg", () =>
        sendRoomMessageRest(token, roomId, { content: "room hi", client_msg_id: cid }),
      );
      return;
    }
    const payload = encodeMsgSend({
      from: session.userId,
      to: roomId,
      chatType: ChatType.CHAT_ROOM,
      msgType: MsgType.MSG_TEXT,
      content: new TextEncoder().encode("room hi"),
      clientMsgId: cid,
    });
    await run("room_msg", () => request(CmdType.CMD_MSG_SEND, payload, { routeKey: roomId }));
  }

  return (
    <div className="panel stack">
      <h2>聊天室 CMD_ROOM_*</h2>
      <div className="row">
        <label>
          通道
          <select value={channel} onChange={(e) => setChannel(e.target.value as Channel)}>
            <option value="ws">WS</option>
            <option value="rest">REST</option>
          </select>
        </label>
      </div>
      <div className="row">
        <label>
          name
          <input value={name} onChange={(e) => setName(e.target.value)} />
        </label>
        <label>
          max_members
          <input value={maxMembers} onChange={(e) => setMaxMembers(e.target.value)} />
        </label>
        <button onClick={() => void create()}>创建</button>
      </div>
      <div className="row">
        <label>
          room_id
          <input value={roomId} onChange={(e) => setRoomId(e.target.value)} />
        </label>
        <label>
          member_uids (kick)
          <input value={targetUid} onChange={(e) => setTargetUid(e.target.value)} />
        </label>
      </div>
      <div className="row">
        <button className="secondary" onClick={() => void join()}>
          Join
        </button>
        <button className="secondary" onClick={() => void leave()}>
          Leave
        </button>
        <button className="secondary" onClick={() => void dismiss()}>
          Dismiss
        </button>
        <button className="secondary" onClick={() => void kick()}>
          Kick
        </button>
        <button className="secondary" onClick={() => void update()}>
          Update
        </button>
        <button className="secondary" onClick={() => void broadcast()}>
          广播消息
        </button>
      </div>
      {info ? <p className="mono">{info}</p> : null}
    </div>
  );
}
