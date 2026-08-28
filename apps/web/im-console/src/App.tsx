import { useEffect, useRef } from "react";
import { NavLink, Navigate, Outlet, Route, Routes } from "react-router-dom";
import { useSyncExternalStore } from "react";
import { revokeSession } from "./api/client";
import { ChannelPage } from "./pages/Channel";
import { ChatPage } from "./pages/Chat";
import { CoveragePage } from "./pages/Coverage";
import { DebugPage } from "./pages/Debug";
import { DevicesPage } from "./pages/Devices";
import { FriendsPage } from "./pages/Friends";
import { GroupsPage } from "./pages/Groups";
import { LoginPage } from "./pages/Login";
import { RoomsPage } from "./pages/Rooms";
import { connectionStore } from "./stores/connection";
import { clearSession, loadSession } from "./stores/session";
import { authenticate, connect, disconnect } from "./ws/imSocket";
import { resolveWsUrl } from "./ws/resolveUrl";

function Shell() {
  const snap = useSyncExternalStore(
    connectionStore.subscribe,
    connectionStore.getSnapshot,
  );
  const session = loadSession();
  const reconnecting = useRef(false);

  useEffect(() => {
    if (!session) return;
    const st = connectionStore.getSnapshot().status;
    if (st !== "idle" && st !== "disconnected") return;
    if (reconnecting.current) return;
    reconnecting.current = true;
    void (async () => {
      try {
        await connect(resolveWsUrl(session.websocketUrls));
        await authenticate({
          appKey: session.appKey,
          userId: session.userId,
          token: session.accessToken,
          deviceId: session.deviceId,
        });
      } catch {
        /* 用户可在 Debug 页查看；登录页可重新登录 */
      } finally {
        reconnecting.current = false;
      }
    })();
  }, [session]);

  if (!session) return <Navigate to="/login" replace />;

  return (
    <div className="app-shell">
      <nav className="nav">
        <div className="brand">
          IM Console
          <span>
            {session.userId}@{session.appKey}
          </span>
        </div>
        <NavLink
          to="/chat"
          className={({ isActive }) => (isActive ? "active" : undefined)}
        >
          消息
        </NavLink>
        <NavLink
          to="/groups"
          className={({ isActive }) => (isActive ? "active" : undefined)}
        >
          群组
        </NavLink>
        <NavLink
          to="/rooms"
          className={({ isActive }) => (isActive ? "active" : undefined)}
        >
          聊天室
        </NavLink>
        <NavLink
          to="/friends"
          className={({ isActive }) => (isActive ? "active" : undefined)}
        >
          好友
        </NavLink>
        <NavLink
          to="/channel"
          className={({ isActive }) => (isActive ? "active" : undefined)}
        >
          通道
        </NavLink>
        <NavLink
          to="/devices"
          className={({ isActive }) => (isActive ? "active" : undefined)}
        >
          设备
        </NavLink>
        <NavLink
          to="/coverage"
          className={({ isActive }) => (isActive ? "active" : undefined)}
        >
          Coverage
        </NavLink>
        <NavLink
          to="/debug"
          className={({ isActive }) => (isActive ? "active" : undefined)}
        >
          Debug
        </NavLink>
        <div style={{ flex: 1 }} />
        <span className={`badge ${snap.status === "authenticated" ? "ok" : "warn"}`}>
          {snap.status}
        </span>
        <button
          className="secondary"
          onClick={() => {
            void revokeSession(session.accessToken).finally(() => {
              disconnect();
              clearSession();
              location.href = "/login";
            });
          }}
        >
          退出
        </button>
      </nav>
      <main className="main">
        <Outlet />
      </main>
    </div>
  );
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route element={<Shell />}>
        <Route path="/" element={<Navigate to="/chat" replace />} />
        <Route path="/chat" element={<ChatPage />} />
        <Route path="/groups" element={<GroupsPage />} />
        <Route path="/rooms" element={<RoomsPage />} />
        <Route path="/friends" element={<FriendsPage />} />
        <Route path="/channel" element={<ChannelPage />} />
        <Route path="/devices" element={<DevicesPage />} />
        <Route path="/coverage" element={<CoveragePage />} />
        <Route path="/debug" element={<DebugPage />} />
      </Route>
    </Routes>
  );
}
