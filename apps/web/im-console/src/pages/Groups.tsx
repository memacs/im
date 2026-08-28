import { useState } from "react";
import {
  createGroupRest,
  groupDismissRest,
  groupInviteRest,
  groupJoinRest,
  groupKickRest,
  groupLeaveRest,
  groupMuteRest,
  groupRemoveAdminRest,
  groupSetAdminRest,
  groupTransferRest,
  groupUpdateRest,
  sendGroupMessageRest,
} from "../api/client";
import {
  ChatType,
  CmdType,
  MsgType,
  encodeGroupCreate,
  encodeGroupOperate,
  encodeMsgSend,
  im,
} from "../protocol/codec";
import { loadSession } from "../stores/session";
import { request } from "../ws/imSocket";

type Channel = "ws" | "rest";

function parseMembers(raw: string) {
  return raw.split(/[,\s]+/).filter(Boolean);
}

export function GroupsPage() {
  const session = loadSession();
  const [name, setName] = useState("demo-group");
  const [members, setMembers] = useState("bob");
  const [groupId, setGroupId] = useState("");
  const [targetUid, setTargetUid] = useState("bob");
  const [announcement, setAnnouncement] = useState("");
  const [channel, setChannel] = useState<Channel>("ws");
  const [info, setInfo] = useState("");

  const token = session?.accessToken ?? "";

  async function run(label: string, fn: () => Promise<unknown>) {
    try {
      const res = await fn();
      const text =
        res === undefined ? "ok" : typeof res === "object" ? JSON.stringify(res) : String(res);
      setInfo(`${label}: ${text}`);
      if (typeof res === "object" && res && "group_id" in res) {
        setGroupId(String((res as { group_id: string }).group_id));
      }
    } catch (e) {
      setInfo(`${label}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  async function create() {
    const memberUids = parseMembers(members);
    if (channel === "rest") {
      await run("create", () =>
        createGroupRest(token, { name, member_uids: memberUids, announcement: announcement || undefined }),
      );
      return;
    }
    await run("create", async () => {
      const payload = encodeGroupCreate({ name, memberUids, announcement });
      const resp = await request(CmdType.CMD_GROUP_CREATE_REQ, payload);
      const body = im.protocol.GroupCreateResp.decode(resp.payload);
      return { group_id: body.groupId, name: body.name };
    });
  }

  async function join() {
    if (channel === "rest") {
      await run("join", () => groupJoinRest(token, groupId));
      return;
    }
    await run("join", () =>
      request(CmdType.CMD_GROUP_JOIN_REQ, encodeGroupOperate({ groupId })),
    );
  }

  async function leave() {
    if (channel === "rest") {
      await run("leave", () => groupLeaveRest(token, groupId));
      return;
    }
    await run("leave", () =>
      request(CmdType.CMD_GROUP_LEAVE_REQ, encodeGroupOperate({ groupId })),
    );
  }

  async function dismiss() {
    if (channel === "rest") {
      await run("dismiss", () => groupDismissRest(token, groupId));
      return;
    }
    await run("dismiss", () =>
      request(CmdType.CMD_GROUP_DISMISS_REQ, encodeGroupOperate({ groupId })),
    );
  }

  async function kick() {
    const uids = parseMembers(targetUid);
    if (channel === "rest") {
      await run("kick", () => groupKickRest(token, groupId, { member_uids: uids }));
      return;
    }
    const payload = im.protocol.GroupKickReq.encode(
      im.protocol.GroupKickReq.create({ groupId, memberUids: uids }),
    ).finish();
    await run("kick", () => request(CmdType.CMD_GROUP_KICK_REQ, payload));
  }

  async function invite() {
    const uids = parseMembers(targetUid);
    if (channel === "rest") {
      await run("invite", () => groupInviteRest(token, groupId, { member_uids: uids }));
      return;
    }
    const payload = im.protocol.GroupInviteReq.encode(
      im.protocol.GroupInviteReq.create({ groupId, memberUids: uids }),
    ).finish();
    await run("invite", () => request(CmdType.CMD_GROUP_INVITE_REQ, payload));
  }

  async function setAdmin() {
    if (channel === "rest") {
      await run("set_admin", () => groupSetAdminRest(token, groupId, targetUid));
      return;
    }
    const payload = im.protocol.GroupAdminReq.encode(
      im.protocol.GroupAdminReq.create({ groupId, memberUid: targetUid }),
    ).finish();
    await run("set_admin", () => request(CmdType.CMD_GROUP_SET_ADMIN_REQ, payload));
  }

  async function removeAdmin() {
    if (channel === "rest") {
      await run("remove_admin", () => groupRemoveAdminRest(token, groupId, targetUid));
      return;
    }
    const payload = im.protocol.GroupAdminReq.encode(
      im.protocol.GroupAdminReq.create({ groupId, memberUid: targetUid }),
    ).finish();
    await run("remove_admin", () => request(CmdType.CMD_GROUP_REMOVE_ADMIN_REQ, payload));
  }

  async function transfer() {
    if (channel === "rest") {
      await run("transfer", () => groupTransferRest(token, groupId, targetUid));
      return;
    }
    const payload = im.protocol.GroupTransferReq.encode(
      im.protocol.GroupTransferReq.create({ groupId, newOwnerUid: targetUid }),
    ).finish();
    await run("transfer", () => request(CmdType.CMD_GROUP_TRANSFER_REQ, payload));
  }

  async function update() {
    if (channel === "rest") {
      await run("update", () =>
        groupUpdateRest(token, groupId, { name, announcement: announcement || undefined }),
      );
      return;
    }
    const payload = im.protocol.GroupUpdateReq.encode(
      im.protocol.GroupUpdateReq.create({
        groupId,
        name,
        announcement,
      }),
    ).finish();
    await run("update", () => request(CmdType.CMD_GROUP_UPDATE_REQ, payload));
  }

  async function mute() {
    const until = Date.now() + 3600_000;
    if (channel === "rest") {
      await run("mute", () =>
        groupMuteRest(token, groupId, { member_uid: targetUid, muted_until: until }),
      );
      return;
    }
    setInfo("mute 仅 REST（服务端 group_mute dispatch）");
  }

  async function sendGroupMsg() {
    if (!session) return;
    const cid = crypto.randomUUID();
    if (channel === "rest") {
      await run("group_msg", () =>
        sendGroupMessageRest(token, { to: groupId, content: "group hi", client_msg_id: cid }),
      );
      return;
    }
    const payload = encodeMsgSend({
      from: session.userId,
      to: groupId,
      chatType: ChatType.CHAT_GROUP,
      msgType: MsgType.MSG_TEXT,
      content: new TextEncoder().encode("group hi"),
      clientMsgId: cid,
    });
    await run("group_msg", () => request(CmdType.CMD_MSG_SEND, payload, { routeKey: groupId }));
  }

  return (
    <div className="panel stack">
      <h2>群组 CMD_GROUP_*</h2>
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
          members
          <input value={members} onChange={(e) => setMembers(e.target.value)} />
        </label>
        <label>
          announcement
          <input value={announcement} onChange={(e) => setAnnouncement(e.target.value)} />
        </label>
        <button onClick={() => void create()}>创建群</button>
      </div>
      <div className="row">
        <label>
          group_id
          <input value={groupId} onChange={(e) => setGroupId(e.target.value)} />
        </label>
        <label>
          target_uid
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
        <button className="secondary" onClick={() => void invite()}>
          Invite
        </button>
        <button className="secondary" onClick={() => void setAdmin()}>
          SetAdmin
        </button>
        <button className="secondary" onClick={() => void removeAdmin()}>
          RemoveAdmin
        </button>
        <button className="secondary" onClick={() => void transfer()}>
          Transfer
        </button>
        <button className="secondary" onClick={() => void update()}>
          Update
        </button>
        <button className="secondary" onClick={() => void mute()}>
          Mute(1h)
        </button>
        <button className="secondary" onClick={() => void sendGroupMsg()}>
          群消息
        </button>
      </div>
      {info ? <p className="mono">{info}</p> : null}
    </div>
  );
}
