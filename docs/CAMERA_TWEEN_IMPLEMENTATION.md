# Camera Tween for Home Teleport — Implementation Plan

This document defines a detailed, end-to-end plan to implement a smooth client-side camera transition ("camera tween") when the player uses the Home teleport. The goal is to replace the current snap transition with a brief, polished glide that respects player perspective, minimizes motion sickness, and plays nicely with existing systems.

## Objectives

- Provide a smooth camera transition during Home teleport, preserving the player’s relative view.
- Keep changes localized, opt‑in, and safe to roll back (feature‑flag gated).
- Avoid conflicts with Roblox’s default camera system and existing client code.
- Handle edge cases: timeouts, repeated teleports, character changes, streaming, and failures.

## Non‑Goals

- Rewriting Roblox’s default camera controller.
- Adding new server remotes or changing server teleport logic.
- Affecting other gameplay teleports by default (opt‑in later).

---

## Current Behavior Summary

- Home teleport is triggered on the client in `client/MiningGame/UI/MainHUD.lua` by calling `ClientRF.call("TeleportToHome")`.
- The server handles respawn in `server/MiningGame/SpawnService.lua` by directly setting `HumanoidRootPart.CFrame` to a computed spawn CFrame (no camera logic).
- With the default Roblox camera, this results in an instantaneous camera snap to the new location.

---

## Design Overview

We will introduce a dedicated client module to manage camera transitions around teleports. The workflow:

1. Before invoking the Home teleport remote, capture the camera’s relative transform to the character’s HumanoidRootPart (HRP).
2. Temporarily set the camera to `Scriptable` to avoid fighting the default camera controller while we animate.
3. Invoke the remote to teleport.
4. Detect the HRP’s transform change indicating the teleport has completed.
5. Compute the target camera CFrame by applying the captured relative transform to the new HRP CFrame.
6. Tween the camera to this target CFrame over a short duration with easing.
7. Restore the camera to `Custom` (default control) on completion or failure.

Optional: fade the screen via PostFX and/or gently fade HUD elements during the transition.

---

## New Module: `CameraTransition`

Location: `client/MiningGame/Camera/CameraTransition.lua`

Responsibilities:

- Own all camera transition state and cancellation logic.
- Provide a simple API to wrap a teleport action and perform the camera tween.
- Integrate optional polish (screen fade) via existing PostFX facilities when enabled.

### Public API (proposed)

- `CameraTransition.wrapTeleport(opts: Options, doTeleport: () -> (boolean, string?)) -> (boolean, string?)`
  - High-level helper that performs the full sequence: capture, scriptable, run `doTeleport`, await HRP movement, tween camera, restore.
  - Returns `(true)` on success, or `(false, reason)` on failure/timeout. Always restores camera mode.

- `CameraTransition.cancel()`
  - Cancels any active transition and restores the camera to default control.

- `CameraTransition.isActive() -> boolean`
  - Indicates if a transition is currently in progress.

### Options (with defaults)

Suggested config structure (read from `GameConfig.Client.CameraTransition`):

- `ENABLED: boolean` (default: `true`)
- `DURATION: number` seconds (default: `0.45`)
- `EASING: Enum.EasingStyle` (default: `Enum.EasingStyle.Quad`)
- `TIMEOUT_SEC: number` (default: `1.5`)
- `USE_FADE: boolean` (default: `false`)
- `HIDE_HUD: boolean` (default: `false`)

Module should gracefully fall back to internal defaults if the config key is absent.

### Internal State

- `_active: boolean` — transition in progress guard.
- `_tween: Tween?` — current tween to allow cancellation.
- `_cframeValue: CFrameValue?` — intermediary for reliable `Completed` and per-step updates (optional but recommended).
- `_connections: {RBXScriptConnection}` — listeners, cleaned on completion.

### State Machine (conceptual)

```
Idle -> (begin) -> Captured -> Scriptable -> Teleporting -> AwaitHRPChange
    -> (changed) -> Tweening -> Restoring -> Idle
    -> (timeout/error) -> Restoring -> Idle
    -> (cancel) -> Restoring -> Idle
```

---

## Detailed Algorithms

### Relative Transform Capture

- Let `cam = workspace.CurrentCamera`, `hrp = character:WaitForChild("HumanoidRootPart")`.
- Capture relative camera transform before teleport:
  - `local rel = hrp.CFrame:ToObjectSpace(cam.CFrame)`
  - This preserves the player’s view direction and offset relative to HRP.

### Detecting Teleport Completion

- Persist `hrp.CFrame` (or position) as `before`.
- After invoking the remote, wait for either:
  - `hrp:GetPropertyChangedSignal("CFrame")`, and then verify a meaningful delta, or
  - Poll for `((hrp.Position - before.Position).Magnitude >= 5)` within a timeout.
- Consider rotation-only changes: if position delta is small but `hrp.CFrame ~= before`, accept.

### Camera Tween

- Compute `targetCam = hrp.CFrame:ToWorldSpace(rel)`.
- Set `cam.CameraType = Scriptable` while tweening.
- Two implementation options:
  1) Directly tween `camera.CFrame` via `TweenService:Create(camera, info, { CFrame = targetCam })`.
  2) Tween a `CFrameValue` from `from = camera.CFrame` to `to = targetCam`, and on each `Changed` assign `camera.CFrame = cframeValue.Value`.

Recommended: Option 2 (CFrameValue) for robust completion events and easier cancellation without leaving residual tweens on `camera`.

### Restoration

- On tween `Completed`, on `cancel()`, or on any failure:
  - Stop active tween and disconnect listeners.
  - If `camera` still exists, set `camera.CameraType = Custom`.
  - Clear internal state flags.

---

## Optional Polish

### PostFX Transition (Screen Fade)

- If `USE_FADE` is enabled:
  - Use `PostFXService.Get()` to obtain the manager.
  - Apply `TRANSITION.screenFade` with a short fade in (e.g., 0.15–0.25s) at teleport start.
  - Maintain during tween, then fade out after camera settles.

Notes:

- The PostFX system blends deterministically; ensure you use the `TRANSITION` layer if needed and remove the effect.
- Respect quality limits defined in PostProcessing config.

### HUD Cross‑Fade

- If `HIDE_HUD` is enabled:
  - From the caller (e.g., in `MainHUD`), use existing helpers `fadeOutChips()` and `fadeInChips()` around the transition.
  - Alternatively, if a HUD instance isn’t accessible in `CameraTransition`, accept optional callbacks `{ onStart, onDone }` supplied by the caller to perform UI fades.

---

## Integration Points

### 1) Home Button in `MainHUD`

- File: `client/MiningGame/UI/MainHUD.lua`
- In the `self.homeButton = HomeButton.new({ onClick = function() ... end })` handler:

Pseudo‑flow:

```
local CameraTransition = require(ReplicatedStorage.MiningGame.ClientPathTo.Camera.CameraTransition)
local GameConfig = require(ReplicatedStorage.MiningGame.GameConfig)

if not GameConfig.Client.CameraTransition.ENABLED then
    -- Fallback: plain RF call (current behavior)
    ClientRF.call("TeleportToHome")
    return
end

-- Optional HUD fade out here (or pass callbacks into wrapTeleport)
CameraTransition.wrapTeleport({
    duration = GameConfig.Client.CameraTransition.DURATION,
    easing = GameConfig.Client.CameraTransition.EASING,
    timeoutSec = GameConfig.Client.CameraTransition.TIMEOUT_SEC,
    useFade = GameConfig.Client.CameraTransition.USE_FADE,
}, function()
    local data, err = ClientRF.call("TeleportToHome")
    return (err == nil), err
end)

-- Optional HUD fade in after completion (via callbacks or after awaited call)
```

Notes:

- Do not hard‑depend on HUD internals from the module; keep UI fades in the caller.
- Respect server cooldown (server already enforces); the client should not block clicks but may ignore if a transition is active.

### 2) Debug Tools (optional)

- Add a toggle in `client/MiningGame/UI/Components/DebugTab.lua` to enable/disable the camera tween flag at runtime (Studio only), reading/writing a local value in a small settings service or in `_G` for testing.

### 3) Tree Climbing (later)

- File: `client/MiningGame/TreeClimbing.client.lua`
- Optional adoption: wrap its `teleportToTreeTop` with the same transition for consistency.

---

## Configuration

Proposed additions to `shared/MiningGame/GameConfig.lua` under `GameConfig.Client`:

```
GameConfig.Client.CameraTransition = {
    ENABLED = true,
    DURATION = 0.45,
    EASING = Enum.EasingStyle.Quad,
    TIMEOUT_SEC = 1.5,
    USE_FADE = false,
    HIDE_HUD = false,
}
```

Fallback behavior:

- If the `CameraTransition` table is missing, the module must use internal defaults and still function safely.

---

## Implementation Steps (Top‑to‑Bottom)

1) Create module directory and file: `client/MiningGame/Camera/CameraTransition.lua`.
2) Import dependencies: `Players`, `RunService`, `TweenService`, `ReplicatedStorage`, `Logger`, `GameConfig`, `PostFXService` (optional).
3) Define module state fields: `_active`, `_tween`, `_cframeValue`, `_connections`.
4) Implement `local function cleanup()` to cancel tween, disconnect listeners, restore camera type to `Custom`, and clear state.
5) Implement `local function waitForHRPChange(hrp, beforeCFrame, timeoutSec)`:
   - Listen on `hrp:GetPropertyChangedSignal("CFrame")`.
   - Also poll with a small heartbeat if necessary; accept either position delta >= threshold (e.g., 5 studs) or any CFrame change.
   - Return `true` on change, `false` on timeout.
6) Implement `local function tweenCamera(fromCFrame, toCFrame, duration, easing)`:
   - Create a `CFrameValue` set to `fromCFrame`.
   - Connect `Changed` to assign `camera.CFrame`.
   - Create tween on the `CFrameValue` to `toCFrame`.
   - Store tween handle for cancellation; on `Completed`, disconnect and destroy `CFrameValue`.
7) Implement `wrapTeleport(opts, doTeleport)`:
   - Guard if `_active` is true → cancel current or return early (decide policy: cancel then continue is preferred).
   - Capture `player`, `character`, `hrp`, `camera`. If missing, just call `doTeleport()` and return.
   - Capture relative transform: `rel = hrp.CFrame:ToObjectSpace(camera.CFrame)`.
   - Switch `camera.CameraType = Scriptable`.
   - If `USE_FADE`, apply screen fade via PostFX (short fade in).
   - Call `doTeleport()` (pcall; treat failure as a no‑op → restore camera and return error).
   - Await HRP change with timeout; on timeout, restore and return error.
   - Compute `targetCam = hrp.CFrame:ToWorldSpace(rel)`.
   - Tween camera from current to target (duration/easing from options or defaults).
   - On tween completion: restore `camera.CameraType = Custom`; if `USE_FADE`, fade out.
   - Return success.
8) Implement `cancel()` to stop active tween and call `cleanup()`.
9) Implement `isActive()` returning `_active`.
10) Defensive coding: multiple `pcall`s around Roblox property sets; nil‑checks on `camera` and `hrp` throughout.
11) Add category logging via `Logger` for Studio debugging (e.g., "CameraTransition").

---

## Safety and Edge Cases

- Always restore `camera.CameraType = Custom` on any path (success, error, timeout, cancel).
- Character respawn mid‑transition:
  - If `Players.LocalPlayer.Character` replaces or `HumanoidRootPart` is destroyed, cancel and restore.
- Reentrancy:
  - If `wrapTeleport` is invoked while active, either:
    - Cancel the in‑flight transition and start a new one, or
    - Return `false, "BUSY"` (choose the former for responsiveness; log it).
- Streaming:
  - `RequestStreamAroundAsync` is server‑side already; on client, the fade can mask pop‑in when enabled.
- Camera shake:
  - Current code reads camera only; no conflict is expected while `Scriptable` is active.
- First‑person/VR:
  - If first‑person or VR is used later, consider disabling the tween or reducing duration via config to avoid discomfort.

---

## Testing Plan

Scenarios:

1) Happy path: press Home; HRP moves; camera tweens smoothly; control restored.
2) Remote failure: server RF fails; camera remains in Custom; no lingering effects.
3) Timeout: HRP does not move; restore camera; return error.
4) Repeated clicks: issue multiple Home requests rapidly; ensure single transition at a time and no dangling tweens.
5) Movement during tween: player moves/turns; camera still completes and hands back control.
6) Character death during tween: cancel safely and restore.
7) Streaming pop‑in: with `USE_FADE=true`, ensure fade covers most artifacts.
8) Mobile devices: verify no UI overlap issues; ensure HUD fades don’t conflict with safe areas.

Verification:

- Studio `Logger` messages indicate each phase and confirm restoration.
- Confirm `camera.CameraType` is `Custom` at the end in all cases.
- Use prints/warns sparingly in production; rely on `Logger` with levels.

---

## Rollout Strategy

- Introduce a feature flag in `GameConfig.Client.CameraTransition.ENABLED` (default `true` in Studio builds; configurable otherwise).
- Expose a toggle in Debug tab (Studio only) to quickly enable/disable during testing.
- Start with Home teleport only; collect feedback; then consider extending to other teleports.

---

## Risks & Mitigations

- Motion sickness for some users → keep duration short (0.35–0.5s) and provide flag to disable.
- Conflicts with default camera → use `Scriptable` only during tween; always restore.
- Edge timing issues (e.g., HRP change too fast/slow) → use both event and polling with a generous timeout.
- Residual tweens or connections → central `cleanup()` called on every exit path.

---

## Acceptance Criteria

- Smooth visual transition occurs on Home teleport with default settings.
- No camera control loss or stuck `Scriptable` state, even on failures/timeouts.
- Feature can be disabled via config without code removal.
- No regressions in UI, sound, or dig feedback.

---

## Implementation Checklist

- [ ] Create `client/MiningGame/Camera/CameraTransition.lua` with API above.
- [ ] Add config section to `shared/MiningGame/GameConfig.lua` (Client.CameraTransition) with defaults.
- [ ] Integrate in `client/MiningGame/UI/MainHUD.lua` Home button handler behind feature flag.
- [ ] Optional: add Debug tab toggle.
- [ ] Optional: apply PostFX screen fade when flag enabled.
- [ ] Test scenarios per Testing Plan; verify logs and restorations.
- [ ] Code review for safety and style; keep changes minimal and localized.

