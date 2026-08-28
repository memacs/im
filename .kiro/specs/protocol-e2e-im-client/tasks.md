# Tasks: protocol-e2e-im-client

- [x] PE2E-01 test.exs 端口 + server + im_client 测试依赖
- [x] PE2E-02 `IM.ClientProtocolCase` 辅助
- [x] PE2E-03 分模块 E2E 测试（19 用例）
- [x] PE2E-04 im_client `notify/3` + Transport 修复
- [x] PE2E-05 服务端 PUSH/帧格式/Sandbox/REST 双通道修复
- [x] PE2E-03 分模块 E2E 测试（23 用例：含 kick/设备限制/阅后即焚）
- [x] PE2E-06 `PGPORT=15432 mise run test` 221 tests 全绿
- [x] PE2E-07 libcluster 跨节点 E2E（`CLUSTER_E2E=1 mix test.cluster`，3 tests 全绿；`sandbox: false` 跨 BEAM 共享 PG）
- [x] PE2E-08 E2E 字段级时序文档 + 实测 JSON（`TRACE_EXPORT=1 mix test test/im_client/protocol/trace_export_test.exs`）
