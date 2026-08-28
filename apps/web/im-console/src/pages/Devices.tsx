import { useEffect, useState } from "react";
import {
  banDeviceRest,
  fetchHealthLive,
  fetchHealthReady,
  localDataClearedRest,
  updatePushTokenRest,
} from "../api/client";
import { loadSession } from "../stores/session";

export function DevicesPage() {
  const session = loadSession();
  const [pushToken, setPushToken] = useState("fcm-demo-token");
  const [healthLive, setHealthLive] = useState("");
  const [healthReady, setHealthReady] = useState("");
  const [info, setInfo] = useState("");

  useEffect(() => {
    void fetchHealthLive()
      .then((r) => setHealthLive(JSON.stringify(r)))
      .catch((e) => setHealthLive(String(e)));
    void fetchHealthReady()
      .then((r) => setHealthReady(JSON.stringify(r)))
      .catch((e) => setHealthReady(String(e)));
  }, []);

  if (!session) return null;

  async function run(label: string, fn: () => Promise<unknown>) {
    try {
      const res = await fn();
      setInfo(`${label}: ${JSON.stringify(res ?? "ok")}`);
    } catch (e) {
      setInfo(`${label}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  return (
    <div className="panel stack">
      <h2>设备 / 健康检查</h2>
      <p className="mono" style={{ color: "var(--muted)" }}>
        device_id={session.deviceId}
      </p>
      <div className="row">
        <label>
          push_token
          <input value={pushToken} onChange={(e) => setPushToken(e.target.value)} />
        </label>
        <button
          onClick={() =>
            void run("push-token", () =>
              updatePushTokenRest(session.accessToken, session.deviceId, pushToken),
            )
          }
        >
          注册 Push Token
        </button>
        <button
          className="secondary"
          onClick={() =>
            void run("local-data-cleared", () =>
              localDataClearedRest(session.accessToken, session.deviceId),
            )
          }
        >
          清本地数据 ACK
        </button>
        <button
          className="secondary"
          onClick={() =>
            void run("ban", () =>
              banDeviceRest(session.accessToken, session.deviceId, {
                reason: "console-test",
              }),
            )
          }
        >
          封禁本设备(MVP)
        </button>
      </div>
      <div className="panel" style={{ marginTop: "0.5rem" }}>
        <h3>服务端健康（无鉴权）</h3>
        <p className="mono">/health/live → {healthLive || "…"}</p>
        <p className="mono">/health/ready → {healthReady || "…"}</p>
      </div>
      {info ? <p className="mono">{info}</p> : null}
    </div>
  );
}
