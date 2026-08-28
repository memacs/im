# Release AUTH 冒烟（IC-07）

依赖：集群已部署、`im` Release 可连 DB。

## 容器内（推荐）

```bash
kubectl -n im-dev exec deployment/im -- /app/bin/smoke-auth
```

等价：`IM.Release.Smoke.auth/0` — 预置临时用户并 REST 登录。

CronJob：`deploy/elixir/im/k8s/im/cronjob-smoke-auth.yaml`（每小时 `:15`）。

## 含 WebSocket 鉴权（im_client）

```bash
export BASE_URL=http://localhost:4000
export APP_KEY=app_demo
export USER_ID=smoke_user
export PASSWORD=password

# 用户不存在时先 provision（loadtest 同源 API）
curl -sf -X POST "$BASE_URL/internal/v1/users/$USER_ID/provision" \
  -H 'x-im-caller-service: ops' -H 'x-trace-id: smoke-auth' \
  -H 'content-type: application/json' \
  -d "{\"app_key\":\"$APP_KEY\",\"password\":\"$PASSWORD\"}"

cd apps/elixir/im_client
mix run -e '
  {:ok, s} = IM.Client.REST.create_session(System.fetch_env!("BASE_URL"), %{
    app_key: System.fetch_env!("APP_KEY"),
    user_id: System.fetch_env!("USER_ID"),
    password: System.fetch_env!("PASSWORD"),
    device_id: "smoke-1"
  })
  ws = hd(s.websocket_urls)
  {:ok, c} = IM.Client.start_link(url: ws)
  :ok = IM.Client.connect(c)
  {:ok, _} = IM.Client.authenticate(c, %{
    app_key: System.fetch_env!("APP_KEY"),
    user_id: System.fetch_env!("USER_ID"),
    token: s.access_token,
    device_id: "smoke-1"
  })
  IO.puts("AUTH OK")
  IM.Client.disconnect(c)
'
```

## 与 messaging 冒烟关系

- [release-smoke-messaging.md](release-smoke-messaging.md) — 消息/会话/未读全链路（Pod 内 Service 层）
- 本文 — REST 登录 + 可选 im_client WS 鉴权
