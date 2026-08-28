# IM Web 演示控制台

独立前端 SPA：浏览器登录、WebSocket 全协议联调，**演示 protocol 定义的全部客户端能力**（非生产 SDK）。

| 项 | 说明 |
| --- | --- |
| 技术栈 | TypeScript + Vite + React + protobufjs |
| 设计 | [web-console.md](../../../docs/design/web-console.md)（DD-037，§3 能力矩阵） |
| 实现说明 | [web-console.md](../../../docs/implementation/web/web-console.md) |
| Kiro Spec | [phase-12-web-console](../../../docs/specs-index.md#phase-013主路线图) |

> **边界**：纯静态前端，**不打进** IM Release；**禁止**调用 `/internal/v1`。

---

## 前置条件

- Node.js 20+（推荐与 CI 一致）
- **IM 服务端已启动**（开发 `im:server` 或 K8s port-forward 到 `:4000`）

---

## 启动

### 安装与代码生成

```bash
cd apps/web/im-console
npm ci
npm run proto          # proto/ → src/protocol/generated（改 proto 后必跑）
```

### 本地开发

```bash
# 终端 A：IM（示例）
mise run k8s-port-forward    # 或 mise run im:server

# 终端 B：Console
mise run web:dev             # http://localhost:5173
```

Vite 将 `/api`、`/ws`、`/health` 代理到 `http://localhost:4000`（见 `vite.config.ts`）。

### 测试与构建

```bash
mise run web:test            # Vitest
mise run web:build           # 产出 dist/
```

---

## 配置

### 开发代理

| 文件 | 说明 |
| --- | --- |
| `vite.config.ts` | `server.port`（默认 5173）、`proxy` 目标（默认 `localhost:4000`） |

若 IM 不在 4000 端口，修改 `vite.config.ts` 中 `proxy` 的 `target`，或在本机用 nginx/Caddy 反代。

### 运行时（浏览器）

Console **无服务端环境变量**。连接 IM 时：

- REST：`POST /api/v1/sessions`（登录页填写 app_key / user_id / password）
- WebSocket：使用登录响应中的 `connection.websocket_urls`，或开发环境走 Vite 代理 `/ws`
- 请求头：REST 必填 `X-Trace-Id`；鉴权后带 `Authorization: Bearer <token>`

### 生产静态站

构建产物为纯静态文件 `dist/`，需配置：

1. **API / WS 同源或 CORS**：浏览器访问的域名须能到达 IM 的 `/api/v1` 与 `/ws`
2. **WebSocket 升级**：Ingress 须支持 `Upgrade`（如 nginx `proxy_http_version 1.1`）
3. **HTTPS**：生产环境 WS 使用 `wss://`

环境相关 base URL 可在构建前通过 Vite 环境变量扩展（当前默认相对路径 + 同源部署）。

---

## 线上部署

Console 为 **静态资源**，与 IM 进程分离部署。

### 构建

```bash
mise run web:build
# 或 cd apps/web/im-console && npm run build
# 产出：apps/web/im-console/dist/
```

### 部署方式（任选）

| 方式 | 说明 |
| --- | --- |
| **对象存储 + CDN** | 上传 `dist/` 到 S3/OSS，配置 SPA fallback 到 `index.html` |
| **Nginx / Caddy** | `root` 指向 `dist/`；`/api`、`/ws` 反代到 IM Service |
| **K8s Ingress** | 一条 Ingress：`/` → console Service，`/api` + `/ws` → `svc/im` |

示例 Nginx 片段（Console 与 IM 同域）：

```nginx
location / {
  root /var/www/im-console/dist;
  try_files $uri /index.html;
}
location /api/ {
  proxy_pass http://im-backend:4000;
}
location /ws {
  proxy_pass http://im-backend:4000;
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "upgrade";
}
```

> 仓库内 **暂无** `deploy/web/im-console/` 官方清单；生产按上述模式自行接入 Ingress。IM 主服务部署见 [deploy-guide.md](../../../docs/implementation/elixir/deploy-guide.md)。

### CI

GitHub Actions `web-console` job：`npm ci` → `vitest` → `vite build`（与 `mise run web:test` / `web:build` 一致）。

---

## 相关文档

- [文档总索引](../../../docs/README.md)
- [功能模块对照表](../../../docs/module-map.md)
- [Kiro Spec 索引](../../../docs/specs-index.md)
- [IM 主服务 README](../../elixir/im/README.md)
- [im_client README](../../elixir/im_client/README.md)（无头自动化，与 Console 分工见设计 §5）
- [apps 总览](../../README.md)
- Coverage 页：本地打开 `/coverage` 对照协议能力矩阵
