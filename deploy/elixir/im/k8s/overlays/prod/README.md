# 生产 K8s Overlay（`im-prod`）

**模板交付**：部署前须替换镜像、域名、外部 PostgreSQL / Redis URL，并 **手动创建 Secret**。  
**禁止**使用 `im-dev` 占位 Secret 或 `overlays/local` 清单直接上生产。

完整流程见 [docs/DELIVERY.md](../../../../docs/DELIVERY.md)。

---

## 与 local / cluster 的差异

| 项 | local / cluster | prod |
| --- | --- | --- |
| 命名空间 | `im-dev` | `im-prod` |
| PG / Redis | 集群内 StatefulSet | **外部托管**（ConfigMap 填 URL） |
| Secret | 开发占位（local） | **外部注入**，本 overlay 删除 dev Secret |
| Ingress | 无（port-forward） | TLS + 公网域名 |
| 冒烟 CronJob | 有 | **已移除** |
| 副本 | local=1 / cluster=2 | 默认 2 + HPA 2–10 |
| 镜像 | `im:local` | 替换为 registry 镜像 |

---

## 部署步骤

### 1. 准备外部依赖

- PostgreSQL 15+：建库、用户，记下连接串
- Redis 7+：多副本 **必须**
- （可选）Kafka：Event Bus，见 [deploy-guide.md](../../../../docs/implementation/elixir/deploy-guide.md) §6

### 2. 构建并推送镜像

```bash
docker build -f deploy/elixir/im/Dockerfile -t <registry>/im:v0.1.0 .
docker push <registry>/im:v0.1.0
```

编辑 `kustomization.yaml`：

```yaml
images:
  - name: im
    newName: <registry>/im
    newTag: v0.1.0
```

### 3. 编辑 ConfigMap

修改 `configmap-prod.yaml`：

- `PHX_HOST` / Ingress `host` / TLS — 统一为对外域名
- `REDIS_URL` — 托管 Redis
- 按需开启 `EVENT_BUS_*`、`UNREAD_FLUSH_AUTO` 等

同步修改 `ingress.yaml` 中的 `host` 与 `tls.secretName`。

### 4. 创建 Secret（必须先于 Deployment）

```bash
kubectl create namespace im-prod --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic im-runtime -n im-prod \
  --from-literal=SECRET_KEY_BASE="$(openssl rand -base64 64 | tr -d '\n')" \
  --from-literal=RELEASE_COOKIE="$(openssl rand -hex 16)" \
  --from-literal=DATABASE_URL="ecto://USER:PASS@pg-host:5432/im_prod"
```

参考 [secret.example.yaml](secret.example.yaml)。

### 5. 数据库迁移

```bash
# 一次性 Job 或本地连生产库执行
kubectl run im-migrate -n im-prod --rm -it --restart=Never \
  --image=<registry>/im:v0.1.0 \
  --env-from=secret/im-runtime \
  --env-from=configmap/im \
  -- bin/im eval "IM.Release.migrate()"
```

（按集群策略调整；亦可在 CI/CD 流水线中执行。）

### 6. 应用清单

```bash
kubectl apply -k deploy/elixir/im/k8s/overlays/prod/
kubectl -n im-prod rollout status deployment/im
```

### 7. 验收

```bash
curl -sf "https://im.example.com/health/ready"
curl -sf "https://im.example.com/metrics" | head
```

---

## 安全提醒

- `/internal/v1` 仅内网 + NetworkPolicy；生产 Ingress **不要** 无鉴权暴露内部 API
- `RELEASE_COOKIE`、`SECRET_KEY_BASE` 轮换须滚动重启全部 Pod
- TLS 证书：`im-tls` Secret 或 cert-manager 自动签发

---

## 相关链接

- [交付手册](../../../../docs/DELIVERY.md)
- [已知限制](../../../../docs/KNOWN-LIMITATIONS.md)
- [deploy-guide.md](../../../../docs/implementation/elixir/deploy-guide.md)
- [k8s README](../README.md)
