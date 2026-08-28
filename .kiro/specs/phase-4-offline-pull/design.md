# Design: Phase 4 离线拉取

`IM.Services.Offline.pull/2` → MessageStore.list_inbox / list_conv  
`IM.WebSocket.Commands.OfflinePull` → RESP  
ConnectionState 放行 `CMD_OFFLINE_PULL_REQ`
