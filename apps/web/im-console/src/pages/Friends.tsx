import { useState } from "react";
import {
  friendAcceptRest,
  friendAddRest,
  friendBlockRest,
  friendDeleteRest,
  friendListRest,
  friendRejectRest,
  friendRequestsRest,
  friendSetRemarkRest,
  friendUnblockRest,
} from "../api/client";
import { CmdType, encodeFriendAdd, encodeFriendList, im } from "../protocol/codec";
import { loadSession } from "../stores/session";
import { request } from "../ws/imSocket";

type Channel = "ws" | "rest";

export function FriendsPage() {
  const session = loadSession();
  const [peer, setPeer] = useState("bob");
  const [requestId, setRequestId] = useState("");
  const [remark, setRemark] = useState("buddy");
  const [channel, setChannel] = useState<Channel>("ws");
  const [info, setInfo] = useState("");

  const token = session?.accessToken ?? "";

  async function run(label: string, fn: () => Promise<unknown>) {
    try {
      const res = await fn();
      setInfo(`${label}: ${JSON.stringify(res ?? "ok")}`);
    } catch (e) {
      setInfo(`${label}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  async function add() {
    if (channel === "rest") {
      await run("add", () => friendAddRest(token, { to_user_id: peer, message: "hi" }));
      return;
    }
    await run("add", async () => {
      const resp = await request(
        CmdType.CMD_FRIEND_ADD_REQ,
        encodeFriendAdd({ toUserId: peer, message: "hi" }),
      );
      return im.protocol.FriendAddResp.decode(resp.payload);
    });
  }

  async function accept() {
    if (channel === "rest") {
      await run("accept", () =>
        friendAcceptRest(token, { request_id: requestId, from_user_id: peer, remark }),
      );
      return;
    }
    const payload = im.protocol.FriendAcceptReq.encode(
      im.protocol.FriendAcceptReq.create({ requestId, fromUserId: peer, remark }),
    ).finish();
    await run("accept", async () => {
      const resp = await request(CmdType.CMD_FRIEND_ACCEPT_REQ, payload);
      return im.protocol.FriendAcceptResp.decode(resp.payload);
    });
  }

  async function reject() {
    if (channel === "rest") {
      await run("reject", () => friendRejectRest(token, { request_id: requestId }));
      return;
    }
    const payload = im.protocol.FriendRejectReq.encode(
      im.protocol.FriendRejectReq.create({ requestId }),
    ).finish();
    await run("reject", () => request(CmdType.CMD_FRIEND_REJECT_REQ, payload));
  }

  async function del() {
    if (channel === "rest") {
      await run("delete", () => friendDeleteRest(token, { friend_user_id: peer }));
      return;
    }
    const payload = im.protocol.FriendDeleteReq.encode(
      im.protocol.FriendDeleteReq.create({ friendUserId: peer }),
    ).finish();
    await run("delete", () => request(CmdType.CMD_FRIEND_DELETE_REQ, payload));
  }

  async function block() {
    if (channel === "rest") {
      await run("block", () => friendBlockRest(token, { user_id: peer }));
      return;
    }
    const payload = im.protocol.FriendBlockReq.encode(
      im.protocol.FriendBlockReq.create({ userId: peer }),
    ).finish();
    await run("block", () => request(CmdType.CMD_FRIEND_BLOCK_REQ, payload));
  }

  async function unblock() {
    if (channel === "rest") {
      await run("unblock", () => friendUnblockRest(token, { user_id: peer }));
      return;
    }
    const payload = im.protocol.FriendUnblockReq.encode(
      im.protocol.FriendUnblockReq.create({ userId: peer }),
    ).finish();
    await run("unblock", () => request(CmdType.CMD_FRIEND_UNBLOCK_REQ, payload));
  }

  async function list() {
    if (channel === "rest") {
      await run("list", () => friendListRest(token));
      return;
    }
    await run("list", async () => {
      const resp = await request(CmdType.CMD_FRIEND_LIST_REQ, encodeFriendList());
      return im.protocol.FriendListResp.decode(resp.payload);
    });
  }

  async function requestList() {
    if (channel === "rest") {
      await run("request_list", () => friendRequestsRest(token));
      return;
    }
    const payload = im.protocol.FriendRequestListReq.encode(
      im.protocol.FriendRequestListReq.create({}),
    ).finish();
    await run("request_list", async () => {
      const resp = await request(CmdType.CMD_FRIEND_REQUEST_LIST_REQ, payload);
      return im.protocol.FriendRequestListResp.decode(resp.payload);
    });
  }

  async function applyRemark() {
    if (channel === "rest") {
      await run("remark", () =>
        friendSetRemarkRest(token, { friend_user_id: peer, remark }),
      );
      return;
    }
    const payload = im.protocol.FriendSetRemarkReq.encode(
      im.protocol.FriendSetRemarkReq.create({ friendUserId: peer, remark }),
    ).finish();
    await run("remark", () => request(CmdType.CMD_FRIEND_SET_REMARK_REQ, payload));
  }

  return (
    <div className="panel stack">
      <h2>好友 CMD_FRIEND_*</h2>
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
          peer user_id
          <input value={peer} onChange={(e) => setPeer(e.target.value)} />
        </label>
        <label>
          request_id
          <input value={requestId} onChange={(e) => setRequestId(e.target.value)} />
        </label>
        <label>
          remark
          <input value={remark} onChange={(e) => setRemark(e.target.value)} />
        </label>
      </div>
      <div className="row">
        <button onClick={() => void add()}>Add</button>
        <button className="secondary" onClick={() => void accept()}>
          Accept
        </button>
        <button className="secondary" onClick={() => void reject()}>
          Reject
        </button>
        <button className="secondary" onClick={() => void del()}>
          Delete
        </button>
        <button className="secondary" onClick={() => void block()}>
          Block
        </button>
        <button className="secondary" onClick={() => void unblock()}>
          Unblock
        </button>
        <button className="secondary" onClick={() => void applyRemark()}>
          Remark
        </button>
        <button className="secondary" onClick={() => void list()}>
          List
        </button>
        <button className="secondary" onClick={() => void requestList()}>
          RequestList
        </button>
      </div>
      {info ? <p className="mono">{info}</p> : null}
    </div>
  );
}
