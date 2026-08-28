# IM 部署文档

本目录按 **语言 / 应用** 组织，与 `apps/` 一一对应。见 [monorepo-layout.md](../docs/implementation/monorepo-layout.md)。

| 语言 | 应用 | 路径 |
|------|------|------|
| Elixir | IM 主服务 | [elixir/im/](elixir/im/) |
| Elixir | 压测 | [elixir/loadtest/](elixir/loadtest/)（Phase 10） |
| Java | IM | [java/](java/)（预留） |

---

## Elixir IM（当前可用）

```text
elixir/im/
├── Dockerfile
├── scripts/release-deploy-local.sh
└── k8s/
    ├── base/          # redis + postgres
    ├── im/            # IM Deployment
    └── overlays/local/
```

```bash
mise run release-deploy
```

详见 [elixir/im/k8s/README.md](elixir/im/k8s/README.md)。

---

## 相关链接

- [docs/implementation/elixir/release-deploy-test.md](../docs/implementation/elixir/release-deploy-test.md)
- [apps/elixir/im/README.md](../apps/elixir/im/README.md)
