Title: Unified Readiness for Cosmetics Rendering

Summary
- Fix the race where cosmetics don’t render on first spawn unless re-equipped.
- Unify readiness checks so cosmetics wait for both server and player data readiness, then perform a single initial sync for the local player.
- Keep remote player cosmetics event-driven only (no global snapshots).
- Event-driven only; add no polling loops.

Motivation
- Current cosmetics bootstrap only waits for ServerReady; if profile DataLoaded is late, the initial GetEquippedItems fails and isn’t retried.
- Re-equipping emits EQUIPMENT_CHANGED which applies cosmetics later, masking the readiness race.
- Spawn orchestration already waits for ServerReady and DataLoaded; cosmetics should follow the same contract.

Requirements
- R1: Local player cosmetics apply automatically on first spawn after both ServerReady and DataLoaded are true.
- R2: No polling. Use one-shot AttributeChangedSignal listeners with auto-disconnect.
- R3: No startup fan-out for remote players; continue using EQUIPMENT_CHANGED only.
- R4: No duplicate applies. Slot-version guards must remain effective.
- R5: Minimal overhead (one RF call per initial spawn for the local player).

Design

Section A — Extend Ready.lua with composite waits
- File: shared/MiningGame/Ready.lua
- Keep existing Ready.wait(timeout?: number).
- Add the following functions:
  - waitServer(timeout?: number): boolean
    - Alias for Ready.wait.
  - waitAttribute(inst: Instance, attrName: string, timeout?: number): boolean
    - Returns true if inst:GetAttribute(attrName) is truthy; otherwise subscribes to inst:GetAttributeChangedSignal(attrName) and waits until truthy or timeout.
    - Disconnect the listener on success or timeout.
  - waitAll(opts: { server?: boolean, playerData?: boolean, timeout?: number, player?: Player }): boolean
    - server defaults to true.
    - playerData defaults to false; when true on client, player defaults to Players.LocalPlayer.
    - Uses a single timeout budget across all waits; if the server wait consumes some time, the remaining time goes to the player data wait.
    - Returns false on timeout for any requested condition.

Implementation details (Ready.lua)
- Add at top: local Players = game:GetService("Players"); local RunService = game:GetService("RunService").
- wait(): keep behavior; in loop, also re-check the attribute after each yield to cover races; wrap Disconnect with pcall.
- waitServer(): return Ready.wait(timeoutSec).
- waitAttribute():
  - Check current attribute via pcall(inst:GetAttribute(attrName)); if truthy, return true.
  - Connect to inst:GetAttributeChangedSignal(attrName), in handler re-check GetAttribute(attrName); if truthy, set done=true.
  - Wait up to timeout with 0.05s yields; on timeout, disconnect; return false.
- waitAll(opts):
  - Compute end time with Time.mono().
  - If server==true: call waitServer(remainingTime).
  - If playerData==true: resolve player (opts.player or LocalPlayer on client); call waitAttribute(player, "DataLoaded", remainingTime).
  - Return true only if all requested conditions succeeded.

Section B — Cosmetics Bootstrap waits for unified readiness
- File: client/MiningGame/Cosmetics/Bootstrap.client.lua
- Always call controller:init() immediately to hook character/equipment events.
- After init:
  - Call: local ok = Ready.waitAll({ server = true, playerData = true, timeout = 20 })
  - If ok == true: call controller:initialSyncLocal()
  - Else (timeout):
    - Attach two one-shot listeners:
      - MiningGame:GetAttributeChangedSignal("ServerReady")
      - Players.LocalPlayer:GetAttributeChangedSignal("DataLoaded")
    - Maintain two flags (serverReady, dataReady) from initial states; update flags in listeners.
    - Define trySync(): if both flags true, call controller:initialSyncLocal(), then disconnect both listeners.
    - Call trySync() once immediately after wiring to cover the race where both were set just before listener creation.

Section C — CosmeticController one-time initial local sync
- File: client/MiningGame/Cosmetics/CosmeticController.lua
- Add field (initialized to false): _didInitialSyncLocal: boolean.
- Add method: initialSyncLocal()
  - If _didInitialSyncLocal then return.
  - If Players.LocalPlayer exists and has Character:
    - local equipped, err = Calls.GetEquippedItems(); if equipped is a table and controller is enabled, call self:_applyCosmetics(Players.LocalPlayer, equipped).
  - Set _didInitialSyncLocal = true at the end.
- Reset on local player removal:
  - In _onPlayerRemoving(player): if player == Players.LocalPlayer then self._didInitialSyncLocal = false end.
- Do not change:
  - _onCharacterAdded: it should continue to handle normal respawn syncing.
  - EQUIPMENT_CHANGED handler: event-driven updates for all players remain unchanged.

Section D — Optional: Add server “data ready” event (Phase 2)
- File: shared/MiningGame/EventNames.lua
  - Add: DATA_READY = "data.ready"
- File: server/MiningGame/DataService.lua
  - Immediately after setting player:SetAttribute("DataLoaded", true), emit:
    - Bus:emit(EventNames.DATA_READY, { to = { kind = "player", player = player }, payload = {} })
- File: client/MiningGame/Cosmetics/CosmeticController.lua
  - Listen for EventNames.DATA_READY for LocalPlayer; if not yet synced, call initialSyncLocal().
- This is optional; the attribute-based readiness already covers the condition. Use if you prefer explicit events.

Edge Cases and Handling
- LocalPlayer has no Character when initialSyncLocal() runs:
  - initialSyncLocal() returns early; existing CharacterAdded logic will fetch/apply on spawn.
- ServerReady set before DataLoaded, or vice versa:
  - The two one-shot listeners handle both orders; trySync() runs when both are true.
- EQUIPMENT_CHANGED arrives while applying cosmetics:
  - Existing slot-version guards in the controller prevent stale/double applies; final result remains correct.

Performance Profile
- Listeners:
  - Two one-shot attribute listeners per initial spawn (ServerReady, DataLoaded); they disconnect immediately after both conditions are met.
- RF calls:
  - One GetEquippedItems call per initial spawn for the local player only.
- Rendering work:
  - Identical to today’s re-equip path; no additional per-frame workload.

QA Checklist
- Slow server start (>10s):
  - Local player cosmetics apply automatically without manual re-equip.
  - Verify only one GetEquippedItems call occurs per initial spawn (temporary logs during testing).
- Normal start:
  - No behavior regression; cosmetics still apply on first spawn.
- Respawn:
  - Cosmetics re-apply as before via _onCharacterAdded.
- Remote players:
  - Cosmetics update on equip/unequip via EQUIPMENT_CHANGED; no startup fan-out.
- No duplicate applies:
  - Confirm slot-version guards prevent duplicates under overlapping events.

Rollout Steps
1) Implement Ready.lua changes (Section A).
2) Update Cosmetics bootstrap (Section B).
3) Add initialSyncLocal() + reset (Section C).
4) Test in Studio (slow and fast starts) and live server.
5) Optional: Add DATA_READY event (Section D) if explicit event is preferred.

Feature Flag (optional)
- Add GameConfig.Features.COSMETICS_WAIT_DATA (default true) if you want an emergency off switch.
  - If false, revert bootstrap to ServerReady-only wait.

Acceptance Criteria
- On both slow and normal starts, local player cosmetics render correctly on first spawn without manual re-equip.
- No additional runtime overhead beyond one initial RF call and transient listeners.
- Remote player cosmetics continue to synchronize using events.
