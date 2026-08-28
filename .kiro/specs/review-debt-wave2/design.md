# Design：Wave 2

- `MessageContext` 扩展 + `from_websocket` / `from_http_client` / `from_http_internal`
- `EventBus.publish(..., write_kafka:)`；`PreSend` 看 `run_hooks`
- `RequireCallerService`：格式 + `internal_api.allowed_callers`
- Channel WS → Dispatch；mute → `:group_mute`
- `ConversationStore.bump_unread/4`
