import { FormEvent, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { createSession } from "../api/client";
import { authenticate, connect } from "../ws/imSocket";
import { resolveWsUrl } from "../ws/resolveUrl";
import {
  clearSession,
  getOrCreateDeviceId,
  saveSession,
} from "../stores/session";

function resolveWsUrlFromSession(urls: string[]): string {
  return resolveWsUrl(urls);
}

export function LoginPage() {
  const nav = useNavigate();
  const [appKey, setAppKey] = useState("demo");
  const [userId, setUserId] = useState("alice");
  const [password, setPassword] = useState("password");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const deviceId = getOrCreateDeviceId();
      const session = await createSession({
        app_key: appKey,
        user_id: userId,
        password,
        device_id: deviceId,
      });
      const urls = session.connection?.websocket_urls ?? [];
      saveSession({
        appKey,
        userId,
        accessToken: session.access_token,
        websocketUrls: urls,
        deviceId,
      });
      await connect(resolveWsUrlFromSession(urls));
      await authenticate({
        appKey,
        userId,
        token: session.access_token,
        deviceId,
      });
      nav("/chat");
    } catch (err) {
      clearSession();
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-wrap">
      <form className="login-card stack" onSubmit={onSubmit}>
        <h1>IM Console</h1>
        <p>协议演示控制台 · platform=web · 不调用 /internal</p>
        <label>
          app_key
          <input value={appKey} onChange={(e) => setAppKey(e.target.value)} required />
        </label>
        <label>
          user_id
          <input value={userId} onChange={(e) => setUserId(e.target.value)} required />
        </label>
        <label>
          password
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>
        {error ? <div className="error">{error}</div> : null}
        <button disabled={busy}>{busy ? "连接中…" : "登录并鉴权"}</button>
        <p className="login-intro-link">
          <Link to="/intro">查看系统功能介绍 →</Link>
        </p>
      </form>
    </div>
  );
}
