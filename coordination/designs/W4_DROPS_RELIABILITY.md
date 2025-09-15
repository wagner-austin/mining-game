# WS-024 — Drops Reliability (Magnet + Forced-claim)

Owner: W4 (Server)
Status: Draft (docs only; code changes behind feature flags/defaults)

## Problem
Some drops can remain in the world orphaned (invalid models, missed cleanup), and owner pickup can feel inconsistent without an always-on magnet.

## Goals
- Zero orphaned drops after a 5-minute dig session
- Smooth owner-first pickup feel without requiring an auto-collect pass
- Preserve ownership/grace semantics; avoid stealing
- Minimal changes reusing the existing, tested inventory and animation paths

## Non-Goals
- No client physics
- No changes to loot math or spawn counts beyond existing config

## Interfaces
- ItemService.lua
  - `activeDrops: {[Model]: DropData}` (owner, itemId, count, spawnTime, claimed)
  - `handleAutoCollection(dt)` (bucketing, AddItemsBulk, flyDropToPlayer, RemoveDrop)
  - `RemoveDrop(model)` (cleanup)
- InventoryService: `AddItemsBulk`, `AddItem`
- Events: `INVENTORY_DELTA`, `CURRENCY_CHANGED`, `ITEM_COLLECTED`

## Feature Flags & Tuning
- Features (optional gates; default enabled if absent)
  - `GameConfig.Features.LOOT_MAGNET_ENABLED = true`
  - `GameConfig.Features.FORCED_CLAIM_ENABLED = true`
- Loot tuning (read if present; fallback to defaults in service)
  - `MAGNET_START_DELAY` (sec, default 0.8)
  - `MAGNET_START_RANGE` (studs, default 12)
  - `MAGNET_MAX_RANGE` (studs, default 35)
  - `MAGNET_GROWTH_SECONDS` (sec, default 3)

## Design

### Owner Magnet (Always-on)
- Compute a per-drop owner magnet radius based on age:
  - If `age < MAGNET_START_DELAY`: `ownerMagnet = 0`
  - Else `t = clamp01((age - delay)/growthSeconds)` and `ownerMagnet = lerp(startRange, maxRange, t)`
- Candidate search radius per player: `max(baseRange, MAGNET_MAX_RANGE)` when magnet is enabled; otherwise existing logic
- Effective pickup range per drop:
  - Owner: `max(ITEM_PICKUP_RANGE, ownerMagnet, autoCollectRange(if any))`
  - Non-owner: unchanged (autoRange if hasAuto, else pickup range)
- Owner-first remains intact via existing grace check

### Forced-claim Safety Sweep (~1 Hz)
- For each active drop not claimed:
  - If invalid (no Parent/PrimaryPart): grant to owner (if present), then `RemoveDrop`
  - Else if `age > ITEM_LIFETIME + DESPAWN_RETRY_DELAY`: grant to owner (if present) or just `RemoveDrop`

### Observability
- One-time INFO logs on enabling magnet/forced-claim
- Avoid spam; rely on existing collection events for telemetry

### Performance
- Owner magnet uses a single candidate query per player per tick, then per-drop range checks (O(n) over nearby)
- Sweep runs at ~1 Hz; lightweight checks only

## Acceptance Tests
- 5-minute dig session: zero orphaned drops; no errors
- Owner-first behavior during grace period preserved
- Inventory deltas and coins unchanged; no double-claim
- flyDropToPlayer still used for visuals

## Rollout Plan
- Default-on via service fallbacks; optionally add flags to GameConfig
- Studio test -> small canary -> enable for all
- Safe rollback: set flags false or revert the file (diff is localized)

## Risks & Mitigations
- Over-collection radius feels too strong: reduce MAX_RANGE or increase delay/growthSeconds
- Edge-case invalid models: handled by sweep; rate-limit any WARN logs if added later
