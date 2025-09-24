EventBus Usage Guide

Scope
- Single global EventBus for cross-module messaging.
- Network events route through RemoteEventBridge; local-only events stay on client/server.

Names and Payloads
- Define event names in `shared/MiningGame/EventNames.lua` and use `EventNames.isValid` for whitelists.
- Server→Client payload shape: `{ to, payload }` where `to` is a strict target and `payload` is event data.
- Local-only (client or server) payloads: emit the data directly (no `to`).

Hot Events (fast-path)
- Mark frequent events to skip middleware: `Bus:markFastPath(EventNames.DIG_FEEDBACK)`.
- Current: `DIG_FEEDBACK`, `SOUND_PLAY`. Consider adding others only after profiling.

Patterns
- Access bus once per module:
  - `local EventBus = require(MiningGame.EventBus)`
  - `local Bus = EventBus.global()`
- Subscribe: `local off = Bus:on(EventNames.ANNOUNCEMENT_BROADCAST, handler)`
- Unsubscribe: call `off()` during cleanup.

Cross-Module Local Events (client)
- `theme.changed` from `ThemeManager.Apply` with `{ name }`.
- `soundtheme.changed` from `SoundThemeManager.Apply` with `{ name }`.
- `account.snapshot.updated` from `AccountDataProvider` with the snapshot table.
- `metrics.updated` from server in response to `metrics.request` (user metrics).
- `metrics.server.updated` from server in response to `metrics.server.request` (aggregate server metrics; Studio-only visibility).

Server→Client Flow
- Emit: `Bus:emit(EventNames.X, { to = target, payload = data })`
- Bridge: `server/MiningGame/RemoteEventBridge.lua` routes whitelisted events.
- Client receives via `client/MiningGame/RemoteEventBridge.client.lua` and re-emits locally.

Do Not Use EventBus For
- Request/response (use `RemoteManager` RFs: `ClientRF`/`RemoteManager`).
  - Exception: metrics push pattern uses a request event + push response for convenience.

Cleanup
- Always keep unsubscribe functions and call them on `Destroying`.
