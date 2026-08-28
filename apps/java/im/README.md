# Java IM 实现（预留）

Java 版 IM 服务端 **尚未实现**，目录为 monorepo 占位，便于后续与 `proto/` 对齐。

| 项 | 说明 |
| --- | --- |
| 状态 | 预留 |
| 协议 | 与 [proto/](../../../proto/) 同源 |
| 文档 | [docs/implementation/java/](../../../docs/implementation/java/) |

---

## 启动

当前无可用应用入口。待实现后预期结构：

```text
apps/java/im/
  pom.xml 或 build.gradle.kts
  src/main/java/...
```

---

## 配置

待定。Elixir 侧环境变量约定见 [release-deploy-test.md](../../../docs/implementation/elixir/release-deploy-test.md)，Java 实现时应保持 **协议与 REST/WS 行为一致**，配置项可对齐同名语义。

---

## 线上部署

占位目录：[deploy/java/](../../../deploy/java/)

生产 IM 请使用已交付的 Elixir 实现：[apps/elixir/im/README.md](../../elixir/im/README.md)。

---

## 相关文档

- [文档总索引](../../../docs/README.md)
- [apps 总览](../../README.md)
- [monorepo-layout.md](../../../docs/implementation/monorepo-layout.md)
- [architecture-overview.md](../../../docs/design/architecture-overview.md)
- [implementation/java/](../../../docs/implementation/java/)（Java 方案预留）
