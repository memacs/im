# Design: Phase 12 Web Console

## 栈

Vite + React + TS；`protobufjs` 从 `proto/` 静态生成；`react-router-dom`。

## 模块

| 路径 | 职责 |
| --- | --- |
| `src/protocol/` | 生成物 + `codec.ts` |
| `src/ws/imSocket.ts` | 连接、AUTH、心跳、重连、收发包 |
| `src/api/` | REST sessions / messages / groups / channels… |
| `src/stores/` | session / connection / messages / debug log |
| `src/pages/` | Login、Chat、Groups、Rooms、Friends、Channel、Coverage、Debug |

## 视觉

开发者工具向：深底 + 青绿强调 + IBM Plex / JetBrains Mono；非营销落地页。
