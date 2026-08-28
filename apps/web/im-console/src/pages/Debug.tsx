import { useSyncExternalStore } from "react";
import { clearDebug, getDebugEntries, subscribeDebug } from "../stores/debugLog";
import { connectionStore } from "../stores/connection";
import { CmdType, im } from "../protocol/codec";

const CMD_NAME: Record<number, string> = Object.fromEntries(
  Object.entries(CmdType)
    .filter(([, v]) => typeof v === "number")
    .map(([k, v]) => [v as number, k]),
);

const COMPRESSION_NAME: Record<number, string> = Object.fromEntries(
  Object.entries(im.protocol.PayloadCompression)
    .filter(([, v]) => typeof v === "number")
    .map(([k, v]) => [v as number, k]),
);

function fmtAuth(auth: im.protocol.IAuthResp | undefined) {
  if (!auth) return null;
  const pc = auth.payloadCompression ?? 0;
  return {
    userId: auth.userId ?? "-",
    heartbeatIntervalSec: auth.heartbeatIntervalSec ?? "-",
    offlinePullLimit: auth.offlinePullLimit ?? "-",
    pushBatchMax: auth.pushBatchMax ?? "-",
    recallWindowSec: auth.recallWindowSec ?? "-",
    editWindowSec: auth.editWindowSec ?? "-",
    payloadCompression: COMPRESSION_NAME[pc] ?? String(pc),
    burnAfterReadEnabled: auth.burnAfterReadEnabled ?? false,
    burnTtlSecDefault: auth.burnTtlSecDefault ?? "-",
    burnTtlSecMax: auth.burnTtlSecMax ?? "-",
    clearLocalData: auth.clearLocalData ?? false,
    serverTime: String(auth.serverTime ?? "-"),
  };
}

export function DebugPage() {
  const entries = useSyncExternalStore(subscribeDebug, getDebugEntries);
  const snap = useSyncExternalStore(
    connectionStore.subscribe,
    connectionStore.getSnapshot,
  );

  return (
    <>
      <div className="panel">
        <div className="row" style={{ justifyContent: "space-between" }}>
          <h2>Debug</h2>
          <button className="secondary" onClick={() => clearDebug()}>
            清空
          </button>
        </div>
        <p className="mono">
          status={snap.status} inbox_seq={snap.inboxSeq} heartbeat=
          {snap.auth?.heartbeatIntervalSec ?? "-"}s
        </p>
        {snap.auth ? (
          <table className="table" style={{ marginTop: "0.75rem" }}>
            <tbody>
              {Object.entries(fmtAuth(snap.auth) ?? {}).map(([k, v]) => (
                <tr key={k}>
                  <td className="mono">{k}</td>
                  <td>{String(v)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <p className="mono" style={{ color: "var(--muted)" }}>
            鉴权成功后展示 AuthResp 配置
          </p>
        )}
        {snap.lastError ? (
          <div style={{ marginTop: "0.75rem", border: "1px solid var(--danger)", padding: "0.5rem" }}>
            <h3>最近 CMD_ERROR</h3>
            <p className="mono">
              code={snap.lastError.code} msg={snap.lastError.msg} ref_cmd=
              {snap.lastError.refCmd} ref_cid={snap.lastError.refCid}
            </p>
          </div>
        ) : null}
      </div>
      <div className="panel">
        <div className="row" style={{ justifyContent: "space-between" }}>
          <h3>下行 PUSH 事件</h3>
          <button className="secondary" onClick={() => connectionStore.clearPushEvents()}>
            清空
          </button>
        </div>
        <div className="msg-list">
          {snap.pushEvents.length === 0 ? (
            <div className="mono" style={{ color: "var(--muted)" }}>
              暂无
            </div>
          ) : (
            snap.pushEvents.map((ev, i) => (
              <div className="msg mono" key={`${ev.ts}-${i}`}>
                {new Date(ev.ts).toLocaleTimeString()} · {ev.kind} · {ev.summary}
              </div>
            ))
          )}
        </div>
      </div>
      <div className="panel">
        <h3>最近 Packet</h3>
        <table className="table">
          <thead>
            <tr>
              <th>dir</th>
              <th>cmd</th>
              <th>seq</th>
              <th>bytes</th>
              <th>note</th>
            </tr>
          </thead>
          <tbody>
            {entries.map((e, i) => (
              <tr key={`${e.ts}-${i}`}>
                <td>{e.dir}</td>
                <td className="mono">
                  {e.cmd} {CMD_NAME[e.cmd] ?? ""}
                </td>
                <td>{e.seq}</td>
                <td>{e.bytes}</td>
                <td>{e.note ?? ""}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
