import { useEffect, useState } from "react";
import { publishChannelRest, subscribeChannelsRest, unsubscribeChannelsRest } from "../api/client";
import {
  CmdType,
  encodeChannelPublish,
  encodeChannelSubscribe,
  im,
} from "../protocol/codec";
import { loadSession } from "../stores/session";
import { onPacket, request } from "../ws/imSocket";

export function ChannelPage() {
  const session = loadSession();
  const [channelId, setChannelId] = useState("fleet:alert");
  const [payload, setPayload] = useState('{"ok":1}');
  const [channel, setChannel] = useState<"ws" | "rest">("ws");
  const [info, setInfo] = useState("");
  const [pushes, setPushes] = useState<string[]>([]);

  useEffect(() => {
    return onPacket((cmd, body) => {
      if (cmd === CmdType.CMD_CHANNEL_PUSH) {
        try {
          const push = im.protocol.ChannelPush.decode(body);
          setPushes((prev) =>
            [`${push.channelId} ${new TextDecoder().decode(push.payload)}`, ...prev].slice(
              0,
              50,
            ),
          );
        } catch {
          /* ignore */
        }
      }
    });
  }, []);

  async function subscribe() {
    if (!session) return;
    try {
      if (channel === "rest") {
        const res = await subscribeChannelsRest(session.accessToken, [channelId]);
        setInfo(`REST subscribe ${JSON.stringify(res)}`);
        return;
      }
      const resp = await request(
        CmdType.CMD_CHANNEL_SUBSCRIBE_REQ,
        encodeChannelSubscribe([channelId]),
      );
      setInfo(`WS subscribe cmd=${resp.cmd}`);
    } catch (e) {
      setInfo(String(e));
    }
  }

  async function unsubscribe() {
    if (!session) return;
    try {
      if (channel === "rest") {
        const res = await unsubscribeChannelsRest(session.accessToken, [channelId]);
        setInfo(`REST unsubscribe ${JSON.stringify(res)}`);
        return;
      }
      const payloadBin = im.protocol.ChannelUnsubscribeReq.encode(
        im.protocol.ChannelUnsubscribeReq.create({ channelIds: [channelId] }),
      ).finish();
      const resp = await request(CmdType.CMD_CHANNEL_UNSUBSCRIBE_REQ, payloadBin);
      setInfo(`unsubscribe cmd=${resp.cmd}`);
    } catch (e) {
      setInfo(String(e));
    }
  }

  async function publish() {
    if (!session) return;
    try {
      if (channel === "rest") {
        const res = await publishChannelRest(session.accessToken, {
          channel_id: channelId,
          payload,
        });
        setInfo(`REST publish ${JSON.stringify(res)}`);
        return;
      }
      const resp = await request(
        CmdType.CMD_CHANNEL_PUBLISH,
        encodeChannelPublish({
          channelId,
          contentType: "application/json",
          payload: new TextEncoder().encode(payload),
          clientEventId: crypto.randomUUID(),
        }),
      );
      setInfo(`WS publish cmd=${resp.cmd}`);
    } catch (e) {
      setInfo(String(e));
    }
  }

  return (
    <div className="panel stack">
      <h2>应用通道 CMD_CHANNEL_*</h2>
      <p className="mono" style={{ color: "var(--muted)" }}>
        下行广播仅服务端 /internal；本页演示订阅与客户端上行。
      </p>
      <div className="row">
        <label>
          channel_id
          <input value={channelId} onChange={(e) => setChannelId(e.target.value)} />
        </label>
        <label>
          payload
          <input value={payload} onChange={(e) => setPayload(e.target.value)} />
        </label>
        <label>
          通道
          <select value={channel} onChange={(e) => setChannel(e.target.value as "ws" | "rest")}>
            <option value="ws">WS</option>
            <option value="rest">REST</option>
          </select>
        </label>
      </div>
      <div className="row">
        <button onClick={() => void subscribe()}>Subscribe</button>
        <button className="secondary" onClick={() => void unsubscribe()}>
          Unsubscribe
        </button>
        <button className="secondary" onClick={() => void publish()}>
          Publish UP
        </button>
      </div>
      {info ? <p className="mono">{info}</p> : null}
      <h3>CHANNEL_PUSH</h3>
      <div className="msg-list">
        {pushes.map((p, i) => (
          <div className="msg mono" key={i}>
            {p}
          </div>
        ))}
      </div>
    </div>
  );
}
