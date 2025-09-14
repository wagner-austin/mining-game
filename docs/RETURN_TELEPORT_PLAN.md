# Return Teleport Feature — Design & Implementation Plan

## Summary

Add a Return button to the HUD, positioned to the right of the existing Home button. When a player presses Home, the server stores their current position/orientation. The UI then shows Return; pressing it teleports the player back to the saved spot and hides Return. The layout reserves space for Return at all times to avoid UI shifting.

## Current State (Assessment)

- Home UI
  - `client/MiningGame/UI/Components/HomeButton.lua` uses `BaseChip` with `Theme.homeButton` sizing.
  - `client/MiningGame/UI/MainHUD.lua` creates `CenterTopGroup` (size `homeButton.width/height`) centered at top; adds a `HomeSlot` child to host the Home button.
  - On click, Home calls `ClientRF.call("TeleportToHome")`.

- Base Chip
  - `client/MiningGame/UI/Components/BaseChip.lua` provides a layered button with show/hide, pulse, and click handling. No “disabled” API, so we’ll rely on fixed-size slots to prevent layout shift.

- Server Teleport
  - `server/MiningGame/RemoteFns/Core.rf.lua` defines `TeleportToHome`, which delegates to `SpawnService:Respawn(player, "TeleportToHome")`.
  - `server/MiningGame/SpawnService.lua` computes the spawn CFrame near the player’s cube and applies it. It requests streaming around the spawn region.
  - No server-side facility currently exists for “return to previous location”.

## Goals & Non‑Goals

- Goals
  - Provide a one-click “Return” to the last pre-Home location.
  - Keep Home/Return chips identical in size and style (use `BaseChip` + `Theme.homeButton`).
  - Prevent UI shifting when Return appears/disappears by reserving its slot.
  - Keep behavior intuitive: Home sets the return target; Return returns once and clears.

- Non‑Goals
  - Cross-server or persistent storage of return targets.
  - Complex validation such as navmesh pathfinding to safe positions (we’ll do basic safety checks only).

## Detailed Design

### State Model (Server)

- Per-player ephemeral map: `previousLocation[userId] = { cframe = CFrame, ts = number }`.
- Set on successful `TeleportToHome` invocation: capture HRP.CFrame immediately before respawning.
- Cleared when:
  - `ReturnToPreviousLocation` succeeds or fails fatally (invalid/missing HRP/target).
  - Player leaves the server (`PlayerRemoving`).

### API (Remote Functions)

1) TeleportToHome (existing)
   - Modify handler to capture and store the player’s current `HumanoidRootPart.CFrame` before calling `SpawnService:Respawn`.
   - Keep existing `opts = { requireProfile = false, rateLimitSec = 0.2 }`.

2) ReturnToPreviousLocation (new)
   - Handler: look up saved cframe; if present, request streaming around position (64 studs), set `HRP.CFrame = saved`, nudge Humanoid to settle, then clear.
   - If missing/invalid, return an error and clear state to avoid stale UI.
   - `opts = { requireProfile = false, rateLimitSec = 0.2 }`.
   - Input schema: zero args.

### Client UX / Layout

- `CenterTopGroup` becomes a fixed-width container that can host two chips side-by-side:
  - Width: `homeButton.width * 2 + chipConfig.gap` (gap from `Theme.currencyChip.gap`).
  - Add a horizontal `UIListLayout` to the group.
  - Create two fixed-size child frames:
    - `HomeSlot` — left slot: size `(homeButton.width, homeButton.height)`.
    - `ReturnSlot` — right slot: same size. Always present (reserved), even when no button exists.

- Components
  - New `ReturnButton.lua` (mirrors `HomeButton.lua`):
    - Uses `BaseChip` with `size = Theme.homeButton.width/height`.
    - Text: “RETURN”. Icon optional; text alone is acceptable for v1.
    - `onClick` callback provided by `MainHUD`.

- Wiring in `MainHUD.lua`
  - Build `CenterTopGroup` at initialization with both slots and a `UIListLayout` (right now it hosts only Home; we will expand it).
  - Home click flow:
    - Call `ClientRF.call("TeleportToHome")`.
    - On success: instantiate `ReturnButton` inside `ReturnSlot`.
    - On failure: log and ensure `ReturnButton` is not visible/created.
  - Return click flow:
    - Call `ClientRF.call("ReturnToPreviousLocation")`.
    - On success: destroy `ReturnButton` and leave `ReturnSlot` empty (slot remains to prevent layout shift).
    - On failure: destroy `ReturnButton`, optionally show a toast, keep slot.
  - Debounce/disable during RF calls to prevent double-activations.

### Safety & Edge Cases

- Missing HRP/character: server handlers return error; client hides Return.
- Blocked/invalid coordinates: we perform a basic set; if Roblox resolves collision badly, player can re-press Home. Optionally, server can raycast for ground height similar to `SpawnService` in a follow-up.
- Streaming: `ReturnToPreviousLocation` requests a local stream around target before teleport to reduce popping.
- Rapid clicks: client disables the chip while an RF is in flight; server rate limits at 0.2s by spec.
- Repeated Home presses: overwrites the saved return target and keeps Return visible.
- Respawn/death/other teleports: not automatically clearing unless Return is used; behavior is strictly “Home enables Return”. This can be revisited if needed.

### Telemetry (Optional)

- Log events (info-level) on server for Home and Return usage for tuning.

## Validation Plan

- Manual tests
  - Press Home: teleport home and see Return appear; press Return: return and hide.
  - Press Home twice: last location used by Return.
  - Spam clicks: ensure only one teleport occurs; UI doesn’t duplicate chips.
  - Character death/respawn: ensure no errors; Return state remains as last set by Home.
  - Mobile (touch): verify chip sizing/touch targets and no layout shift.

## Implementation Steps

1) Server — Core RFs
   - Update `server/MiningGame/RemoteFns/Core.rf.lua`:
     - Add `previousLocationByUserId` table at module scope.
     - In `TeleportToHome` handler: capture `HRP.CFrame` into map before respawn.
     - Add `ReturnToPreviousLocation` RF spec with zero-arg schema, no profile, 0.2s rate limit.
     - On player removal, clear map entry (hook where appropriate—either here or via `Players.PlayerRemoving`).

2) Client — Components
   - Add `client/MiningGame/UI/Components/ReturnButton.lua` implemented with `BaseChip`.

3) Client — HUD Layout & Wiring
   - In `client/MiningGame/UI/MainHUD.lua`:
     - Change `CenterTopGroup` to fixed width for two chips; add horizontal `UIListLayout`.
     - Create `HomeSlot` and `ReturnSlot` frames.
     - Instantiate `HomeButton` in `HomeSlot`.
     - On Home success, create `ReturnButton` in `ReturnSlot`.
     - On Return success or error, destroy `ReturnButton` (keep slot).
     - Add simple in-flight flags to prevent double-invokes.

4) Theme (Optional)
   - If we want an icon for Return later, add `Theme.icons.return` and wire it to `ReturnButton`.

5) Documentation
   - Keep this plan up-to-date and add a brief note to `docs/UI_SYSTEM.md` in a follow-up PR if needed.

## Rollback Plan

- Revert HUD changes to a single-slot `CenterTopGroup` and remove `ReturnButton` and server RF additions. No data migrations needed.

## Risks & Trade‑offs

- Home button will no longer be perfectly centered (it will sit to the left within a two-chip center group). This avoids any motion when Return appears but slightly changes initial alignment. If centering Home is mandatory, we would need a different layout strategy and accept a shift when Return shows.
- Teleporting to a saved CFrame may occasionally place the player awkwardly if the world changed since saving; adding a ground-ray safety pass is possible later.

## Open Questions

- Icon for Return: text-only acceptable, or add a specific glyph?
- Clear Return on character death/respawn automatically?
- Enforce a broader cooldown (`GameConfig.TELEPORT_COOLDOWN`) across both RFs?
- Should Return persist through UI reloads in the same session?

## Estimates

- Server RF updates: 30–45 min
- UI layout changes + ReturnButton: 45–60 min
- Wiring, debouncing, manual testing: 45–60 min
- Total: ~2.5–3 hours including polish

