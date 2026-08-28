import { COVERAGE } from "./coverageData";

export function CoveragePage() {
  const demo = COVERAGE.filter((c) => c.status === "可演示").length;
  const pendingIm = COVERAGE.filter((c) => c.status === "待服务端").length;

  return (
    <div className="panel">
      <div className="row" style={{ justifyContent: "space-between" }}>
        <h2>协议 Coverage</h2>
        <div className="row">
          <span className="badge ok">可演示 {demo}</span>
          <span className="badge warn">待服务端 {pendingIm}</span>
        </div>
      </div>
      <p style={{ color: "var(--muted)", fontSize: "0.9rem" }}>
        对齐设计文档 §3.2；验收以「可演示 + 仅因 IM deferred 的待服务端」为通过。
      </p>
      <table className="table">
        <thead>
          <tr>
            <th>域</th>
            <th>能力</th>
            <th>WS</th>
            <th>REST</th>
            <th>状态</th>
            <th>备注</th>
          </tr>
        </thead>
        <tbody>
          {COVERAGE.map((c) => (
            <tr key={c.id}>
              <td>{c.domain}</td>
              <td>{c.name}</td>
              <td className="mono">{c.ws ?? "—"}</td>
              <td className="mono">{c.rest ?? "—"}</td>
              <td>
                <span
                  className={`badge ${
                    c.status === "可演示" ? "ok" : c.status === "待服务端" ? "warn" : "danger"
                  }`}
                >
                  {c.status}
                </span>
              </td>
              <td>{c.note ?? ""}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
