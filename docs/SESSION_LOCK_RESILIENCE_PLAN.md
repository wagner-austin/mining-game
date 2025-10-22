# Session Lock Resilience & Studio Fallback Plan

Status: Proposed (not yet implemented)

Owner: Server/Data platform

Last updated: 2025-09-13

## Summary

Players can be kicked during join when the session lock acquisition (MemoryStore) fails or is slow, even in Studio, producing logs like:

- Failed to acquire lock for <Player>
- Failed to load profile in production for <Player>

We will harden the session-lock path, improve diagnostics, and add a safe Studio fallback to avoid unnecessary kicks during development.

## Background

Current profile loading flow (simplified):

1) `DataService:LoadPlayerAsync(player)` checks existing lock, then tries to acquire a lock using MemoryStore SortedMap. If the lock cannot be acquired, it returns `nil` and the client is kicked in the production path.

Key code:

- Lock helpers and usage:
  - `server/MiningGame/DataService.lua:479` — `acquireSessionLock(userId)` (SortedMap SetAsync)
  - `server/MiningGame/DataService.lua:497` — `isSessionLocked(userId)` (SortedMap GetAsync + TTL check)
  - `server/MiningGame/DataService.lua:514` — `LoadPlayerAsync(player)` (invokes lock helpers)
- Kick on production failure:
  - `server/MiningGame/DataService.lua:1174` — kicks if no profile loaded and DataStore is considered enabled
- MemoryStore timeouts/retries:
  - `shared/MiningGame/LoadingConstants.lua:14` — `MemoryStoreOp = 4.0` seconds, retries = 2
- Lock TTL:
  - `shared/MiningGame/GameConfig.lua:686` — `SESSION_LOCK_TTL = 60` seconds

Observed behavior: DataStore handles can initialize successfully (so the code treats environment as “production”), while MemoryStore operations may still fail or be slow (Studio API access off, transient issues). That leads to a kick instead of a safe fallback.

## Goals

- Increase resilience of session locking against transient slowness or MemoryStore hiccups
- Provide clear diagnostics when lock acquisition fails (include underlying error)
- In Studio, avoid kicking on lock failures; synthesize defaults and continue
- Preserve production safeguards against multi-login conflicts

## Non‑Goals

- No DataStore schema changes
- No changes to Remote architecture or client readiness sequencing

## Proposed Changes

We will deliver this in three phases for fast mitigation and safe rollout.

### Phase 1 — Quick Hardening (Low risk)

1) Increase MemoryStore operation budget for locking
   - Raise `LoadingConstants.TIMEOUTS.MemoryStoreOp` from 4.0 to 8.0–10.0 seconds
   - Raise `LoadingConstants.RETRY.MemoryStore.attempts` from 2 to 3 (jittered backoff remains)
   - Rationale: transient slow paths should not fail the entire join

2) Improve error logging for lock paths
   - When `_msCall` returns `(ok=false, err)`, include `err` in warning logs:
     - On `acquireSessionLock` failure: log reason (throttled via `ErrorService`)
     - On `isSessionLocked` read failures: log reason at debug level

3) Add Studio‑only fallback when lock acquisition fails
   - If `RunService:IsStudio()` and profile loading fails strictly due to lock unavailability, synthesize default profile/cube and mark `DataLoaded = true` instead of kicking
   - Preserve existing “production” kick behavior when not in Studio

### Phase 2 — Lock Semantics & Robustness (Moderate)

4) Switch to UpdateAsync CAS semantics for locks
   - Use `SortedMap:UpdateAsync(key, transform)` to implement a compare‑and‑set lock with a payload:
     - `{ lockTime = now, serverJobId = game.JobId, sessionId = HttpService:GenerateGUID(false) }`
   - Acquisition rule: if value is nil or expired (now − lockTime ≥ TTL), write new payload; else deny
   - Benefits: atomicity; eliminates race between is‑locked and set

5) Add lock renewal (optional)
   - If desired, periodically refresh lock within TTL window while the player is connected
   - On player leave/BindToClose, clear the lock (already present via `releaseSessionLock`)

### Phase 3 — Observability & Guardrails (Optional)

6) Emit counters and structured events
   - EventBus server events for:
     - `lock_acquire_ok`, `lock_acquire_fail` (with reason), `lock_release`
   - Optional: wire into `UserMetricsService` for dashboards

7) Feature flags
   - Gate Studio fallback, timeout values, and CAS logic behind `GameConfig.Debug` or `GameConfig.Features`
   - Enables gradual rollout and quick rollback

## Implementation Details

Files to touch and changes:

- `shared/MiningGame/LoadingConstants.lua`
  - Increase `TIMEOUTS.MemoryStoreOp` to 8.0–10.0 seconds
  - Increase `RETRY.MemoryStore.attempts` to 3

- `server/MiningGame/DataService.lua`
  - Enhance logging in lock helpers to include `_msCall` error message
  - Studio fallback in `onPlayerAdded` path when lock fails, even if DataStore access is available
  - Phase 2: refactor `acquireSessionLock` and `isSessionLocked` to CAS via `UpdateAsync`

- `shared/MiningGame/GameConfig.lua`
  - Optionally add feature flags:
    - `Features.SESSION_LOCK_CAS = true|false`
    - `Features.STUDIO_FALLBACK_ON_LOCK_FAIL = true|false`
  - Keep `SESSION_LOCK_TTL` unchanged (60s)

## Rollout Plan

1) Phase 1 first (mitigation):
   - Raise timeouts/retries, add error logging, Studio fallback
   - Verify in Studio (API services off/on) and a test private server

2) Phase 2 next (CAS):
   - Behind `Features.SESSION_LOCK_CAS` flag; enable in dev, then production

3) Phase 3 observability:
   - Incremental; non‑functional changes only

## Testing Plan

Scenarios to validate:

- Studio with API Services disabled:
  - Ensure defaults are synthesized; no kick; warning logged

- Studio with API Services enabled but MemoryStore throttled/slow:
  - Temporarily lower `TIMEOUTS.MemoryStoreOp` to force timeouts; confirm fallback (Studio) and logs

- Duplicate session in production (two servers):
  - Ensure CAS logic denies second lock; first session unaffected; second session logs and kicks

- Normal production case:
  - Ensure no regressions in join performance and no spurious warnings

Manual steps:

1) Simulate slow lock:
   - Temporarily set `MemoryStoreOp` to a very small value (e.g., 0.05) and observe fallback behavior in Studio

2) Simulate active lock:
   - Manually set a far‑future `lockTime` via a script or by disabling release; confirm join is denied/kicked in production; fallback in Studio

3) Validate logs:
   - Check logs include MemoryStore error text where applicable

## Risks & Mitigations

- Risk: Longer MemoryStore timeouts delay join on genuine hangs
  - Mitigation: cap at 8–10s, retry count small, keep Studio fallback

- Risk: CAS implementation bugs could allow concurrent sessions
  - Mitigation: keep TTL check; add metrics; staged rollout behind feature flag

- Risk: Studio fallback masks production issues
  - Mitigation: emit loud warnings/events when fallback is used

## Acceptance Criteria

- Studio never kicks due to lock acquisition failures; defaults synthesized with warning
- Production tolerates transient MemoryStore slowness within new budgets (up to ~8–10s)
- CAS locking prevents race between check and set; no duplicate sessions admitted
- Logs include concrete MemoryStore error reasons at the failure site

## Work Items

1) Update `LoadingConstants` timeout/retry for MemoryStore
2) Improve DataService lock error logs and Studio fallback path
3) Add feature flags in `GameConfig`
4) Implement CAS with `UpdateAsync` and payload schema `{ lockTime, serverJobId, sessionId }`
5) Add metrics/events for lock outcomes
6) Document and roll out progressively; verify with test plan

## Open Questions

- Do we want to renew locks periodically, or is TTL + join‑only sufficient?
- Should we display a user‑facing message on Studio fallback to make it obvious during QA?
- Do we want to export lock health to an in‑game admin panel?

## Decision Log

- 2025‑09‑13: Agreed to Phase 1 + Phase 2 approach; Phase 3 optional

