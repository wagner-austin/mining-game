# Auto-Dig Toggle — Plan

Owner: Dig/Systems
Status: Draft
Last updated: 2025-10-13

## Summary
Add a player-controlled, persisted toggle for Auto Dig. Respect across sessions; gate all server auto-starts; provide Settings UI and a PC hotkey. Do not auto-start when disabled even if eligible.

## Goals
- Player can enable/disable Auto Dig at will.
- Preference persists and is respected on join and purchase events.
- Reduce client RE spam when disabled.
- Minimal, surgical changes.

## UX
- Settings Toggle (mobile + desktop):
  - Location: Settings panel → Account (or later “Gameplay”).
  - Label: "Auto Dig"; persists immediately.
- Hotkey (desktop):
  - Key: `T`; show mini toast "Auto Dig: On/Off".
- Edge:
  - ON without pass/boost: save pref; no loop; small notify.
  - OFF with pass/boost: stop loop immediately; stays off.

## Data Model
- `profile.preferences.autoDigEnabled: boolean`.
  - Default: true (preserve status quo). If owns `AUTO_DIGGER`, also true.
  - Stored in `profile.preferences`; ensure map exists.

## Server Semantics
1) Gate starts:
   - In `DigService` listeners for `AUTO_DIG_START` and `CUBE_ORIGIN_CHANGED`, only call `StartAutoDig` if pref is true.
2) Stop when disabled:
   - On toggle false: `StopAutoDig(player)` and clear any pending auto-start.
3) Optional loop guard:
   - In `Dig/Dig/AutoLoop.lua`, exit early if pref becomes false.
4) Client RE throttling:
   - `AutoDig_SetTarget` client sender fires only when pref is true.

## API
- RF `AutoDig_SetEnabled(enabled: boolean)` (prefer in `RemoteFns/Dig.rf.lua`).
  - Rate limit ~0.2–0.5s; validate boolean.
  - Persist pref; start if `enabled && eligible && cubeReady` else return `eligible=false`.
  - Return: `{ ok, success, enabled, eligible? }`.
- Current state: include `autoDigEnabled` in `GetAllSettings` (or add `GetAutoDigEnabled`).

## Client Integration
- Settings: add toggle bound to RF; initialize from server state.
- Hotkey: new client script toggles via RF; shows toast.
- Target sender: gate RE firing on current enabled state.

## Rollout & Defaults
- Backfill: when pref nil → set true (and keep off only if user later disables).
- Monetization: purchase still emits; start only if pref true.

## Telemetry
- Log `auto_dig_pref_changed` (uid, enabled).
- Existing start/stop logs cover loop transitions.

## Test Plan
- Defaults: new players (with/without pass) reflect defaults; no unexpected start.
- Toggle on/off: starts/stops loop appropriately; RE gated.
- Enable w/o eligibility: saved; later boost starts only if still enabled.
- Join/respawn: pref respected in both listeners.

## Work Breakdown
1) DataService: ensure preferences map; getters/setters; queue save.
2) DigService: gate listeners; clear pending on disable.
3) AutoLoop: optional defensive exit on pref=false.
4) RemoteFns: `AutoDig_SetEnabled`; expose current state.
5) Client: settings toggle; hotkey; gate target sender.
6) QA: logs, edge cases, RE drop when disabled.

## Files To Touch
- Server: `server/MiningGame/DataService.lua`, `server/MiningGame/DigService.lua`, `server/MiningGame/Dig/AutoLoop.lua`, `server/MiningGame/RemoteFns/Dig.rf.lua`.
- Client: `client/MiningGame/UI/Panels/SettingsPanel.lua`, `client/MiningGame/AutoDigToggle.client.lua` (new), `client/MiningGame/AutoDigTarget.client.lua`.

## Acceptance Criteria
- Pref persisted and respected; no auto-start when disabled.
- Toggle starts/stops loop immediately.
- Target RE suppressed when disabled.
- UI + hotkey control the same server-backed setting.

