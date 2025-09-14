# Engineering Standards (Draft)

Owner: Manager (final sign‑off). This draft consolidates current patterns for consistency across workers.

Contents
- Dependency Injection & Services
- Remote Functions (RFs) & Event Contracts
- Logging & Observability
- Error Handling
- UI Patterns
- Types & Strictness (Luau)
- Feature Flags & Configuration
- Testing & QA
- Worker Task Links

## Dependency Injection & Services
- Use a DI container (ServiceContainer) to resolve services at init/start time.
- Validate dependencies with `ServiceValidator.get/tryGet(container, name, { methodList? })`.
- Keep services small and single‑purpose; no circular waits; avoid lazy `WaitForChild` outside bootstrap.
- Emit and consume events through `EventBus.global()` with typed contracts in `shared/MiningGame/EventContracts.lua`.
- Guard Roblox APIs and heavy IO via `ErrorService.safecall` with context tags.

## Remote Functions (RFs) & Event Contracts
- RF modules live under `server/MiningGame/RemoteFns/*.rf.lua` and export a factory: `(container) -> { RFSpec }`.
- RFSpec fields: `name`, `handler(ctx, ...)`, `validate(...) -> boolean`, `opts = { requireProfile?, rateLimitSec?, debugOnly? }`.
- Standard result shape: `{ ok: boolean, success: boolean, ... }`. Include error tags (e.g., `RATE_LIMIT`, `INVALID_INPUT`, `NOT_AVAILABLE`).
- Validate inputs strictly; clamp lists; enforce rate limits (typ. 0.2–0.5s) to prevent spam.
- Prefer shared schema validators where available; otherwise encode concise `validate` checks per RF.

## Logging & Observability
- Use `Logger` per module: `local log = Logger.new("ModuleName")`.
- Levels: DEBUG (dev traces), INFO (state changes), WARN (recoverable anomalies), ERROR (rejections/bugs).
- Avoid `print`; do not log inside tight loops. Add high‑signal logs around RF entry/exit and error branches.
- Add lightweight telemetry modules when repeated counters are useful (e.g., Dig Telemetry).

## Error Handling
- Wrap risky Roblox calls with `ErrorService.safecall("context", fn, meta?)`.
- Fail closed on invalid input; return normalized error results without throwing.
- Record enough context (ids, sizes, positions) for repro without leaking PII.

## UI Patterns
- Compose UI with `BasePanel`, `TabbedPanel`, `BaseChip`, `Theme`, `ThemeRefresher`, and `UIUtils`.
- Register and show scenes through `UIManager:showScene/hideScene`; use unique scene names.
- Use `Theme.animations` for tweens; no ad‑hoc `TweenInfo` literals in code paths.
- Respect device safe areas; set `ZIndexBehavior` properly; avoid blocking camera unless intended.

## Types & Strictness (Luau)
- Start files with `--!strict`; type annotate public functions and data records.
- Keep modules small and single‑purpose; avoid globals.
- Add invariants via assertions in debug paths when clamping/indexing.
- Place new behavior behind `GameConfig.Features` flags with safe defaults.

## Feature Flags & Configuration
- Define flags under `GameConfig.Features`; default to safe/disabled until approved.
- Gate debug/studio‑only endpoints via `opts.debugOnly = true` and/or studio checks.
- Document flags in PRs and in worker briefs; include rollout plan.

## Testing & QA
- Manual Studio tests for happy/edge paths; include short "Test Notes" in PRs.
- Verify rate limits, no double‑spend, no negative currency, and correct inventory deltas.
- For terrain/drops, validate no orphans/stuck entities and acceptable performance.
- Keep PRs small and descriptive; update coordination docs and link WS IDs.

## Worker Task Links
- W1 (Cosmetics/Perks): coordination/workers/W1.md
- W2 (UI Nav/Inventory): coordination/workers/W2.md
- W3 (Shop RF/Catalog): coordination/workers/W3.md
- W4 (Drops Reliability): coordination/workers/W4.md
- W5 (Shop UI/Index): coordination/workers/W5.md
- W6 (QA/Docs): coordination/workers/W6.md

See also: coordination/REORG_2025-09-14.md for release‑day specifics and milestones.
