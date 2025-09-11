# Digging Refactor Plan: Volumes, Islands, Performance

This document captures a concrete, step‑by‑step plan to support mining both player cubes and spawned islands (including rectangular prisms), while preserving performance on low‑end PCs and keeping the current service boundaries intact.

## Goals
- Unify digging so players can mine:
  - Their own cube (existing).
  - Spawned islands (rectangular prism volumes).
- Preserve server authority, anti‑cheat, and good performance.
- Minimize changes to existing architecture; avoid premature splitting.
- Leave a clean seam for later additions (e.g., destructible rocks and new shapes).

## Current Architecture (Summary)
- DigService (server):
  - Validates/snap-to player cube only; checks exposed terrain; cooldowns; calls GridService:ApplyDig; rolls loot/sounds; hold‑dig.
  - Caches per‑player `{ origin: CFrame, model: Model }` in `playerCubes`.
- GridService (server):
  - Terrain engine: chunk state, `Read/WriteVoxels`, batching/throttling, dominant material for SFX.
  - Assumes axis‑aligned cube bounds using `GameConfig.Grid.CUBE_SIZE_STUDS` for clamping.
- DataService (server):
  - Persists player data and cube state (`Types.CubeState`).
- FloatingIslandService (server):
  - Builds terrain for islands (FillBlock), but no dig registry/state.

## Gaps
- Validation/snapping hardcoded to the player cube; islands are not mineable.
- GridService clamps to a single global cube size (no rectangular prism bounds).
- Hold‑dig loop assumes the player cube origin.

## Minimal Refactor (Phase 1)
Keep services mostly intact and add a lightweight volume layer inside DigService.

### 1) Add Volume Registry (inside DigService)
- Volume record (axis‑aligned only):
  - `id: string` (e.g., `"cube:<userId>"`, `"island:<seed|uuid>"`)
  - `kind: "cube" | "island"`
  - `origin: CFrame` (center of volume)
  - `sizeStuds: Vector3` (full extents in studs; rectangular prism)
  - `state: Types.CubeState` (in‑memory; created via GridService:CreateCubeState)
  - `permissions: { public: boolean, ownerUserId?: number }` (starter)
  - `meta: { themeId?: string, preset?: string }` (optional)
- API (DigService):
  - `RegisterVolume(v: Volume) -> Volume` (stores/returns)
  - `UnregisterVolume(id: string) -> boolean`
  - `PickVolume(worldPos: Vector3, player: Player?) -> Volume?`:
    - Try player cube volume first.
    - Otherwise test islands (AABB with small epsilon/tolerance).
    - Resolve conflicts by priority: cube > island > others.

### 2) Generalize Snap + Validation
- Add `snapInsideIfNearAABB(worldPos, origin, sizeStuds, epsilons) -> (ok, adjustedPos)`
  - Same logic as current “near cube” snap; compute local offset relative to `origin.Position`; clamp by `sizeStuds/2` per axis.
- Keep `TerrainSurfaceDetector.CheckCellSurface` unchanged (world‑space).
- Replace cube‑only validation path with:
  1) `volume = PickVolume(...)` (deny if none).
  2) Try `snapInsideIfNearAABB` with face/edge/corner eps (same values as cube flow).
  3) Surface check at adjusted position.

### 3) ProcessDigRequest Becomes Volume‑Aware
- Convert world→cell with `GridMath.worldToCell(adjustedPos, volume.origin, CELL_SIZE)`.
- Clamp using `volume` extents (Phase 2 change in GridService; see below).
- Call `GridService:ApplyDig(player, volume.origin, volume.state, cx, cy, cz, size)`.
- Build loot and sounds as today; optionally pass `volume.meta.themeId` later.
- Return `volumeId` or `volumeOrigin` in DigResult for hold‑dig continuity.

### 4) Hold‑Dig Continuity
- Edit `runHoldLoop` (DigService) to use the `volumeOrigin` from the last `ProcessDigRequest` result when stepping deeper with `GridMath.cellToWorld`.
- If no volume info returned (back‑compat), default to the player cube.

### 5) FloatingIslandService Wiring
- On island creation:
  - Compute `origin = CFrame.new(cubePos)` and `sizeStuds = cubeSize`.
  - Call `DigService:RegisterVolume({ id, kind="island", origin, sizeStuds, state=GridService:CreateCubeState(...), permissions={ public=true }, meta={ themeId?, preset? } })`.
- On island removal: `DigService:UnregisterVolume(id)`.

## GridService Changes (Phase 2)
Support rectangular prism volumes and per‑axis clamping without changing I/O paths.

- Today `ApplyDig` computes `halfCells = (CUBE_SIZE_STUDS / CELL_SIZE)/2` and clamps x/y/z to `[-halfCells, halfCells-1]` for all axes.
- Change to per‑axis clamp (derive from `volume.state` or from parameters):
  - `halfX = (sizeStuds.X / CELL_SIZE) / 2`, likewise `halfY`, `halfZ`.
  - Clamp each axis separately using these half‑extents.
- No changes to `WriteCellsToTerrain`: it already builds a region from the cell set and origin.
- State:
  - Extend `Types.CubeState` or add a `VolumeState` variant that includes extents (cell half‑sizes per axis) if needed by clamps/serialization.
  - Islands can remain ephemeral (no persistence) in Phase 1–2.

## Security & Performance
- Server authority:
  - Validation strictly server‑side (volume membership + surface exposure).
  - Snap‑inside logic prevents “overhang” clicks from being rejected while blocking far outside hits.
- Throttling & batching:
  - Keep `GridService` write throttle as is; add per‑volume write budgets later if needed.
  - `ApplyDig` stays single‑call per dig; consider a future batcher module only if hotspots arise.
- Spatial search:
  - If island count grows, add an optional spatial hash for volumes in DigService to avoid O(n) checks.
- Client preview (optional):
  - Add RF `QueryVolumeAt(position)` for perfect preview snapping. Not required to ship mining.

## API Sketch (Non‑Binding)
- DigService (additions):
  - `RegisterVolume(v: Volume): Volume`
  - `UnregisterVolume(id: string): boolean`
  - `PickVolume(worldPos: Vector3, player: Player?): Volume?`
  - `ProcessDigRequest(player, worldPos): DigResult`  // returns `volumeId` or `volumeOrigin`
- FloatingIslandService:
  - On `GenerateIsland`: call `RegisterVolume` with island bounds.
  - On `ClearAllIslands`: call `UnregisterVolume` per island.
- Types (shared):
  - `export type Volume = { id: string, kind: "cube" | "island", origin: CFrame, sizeStuds: Vector3, permissions: { public: boolean, ownerUserId?: number }, meta: { themeId?: string, preset?: string }?, state: CubeState }`

## Implementation Steps & Order
1) DigService: Add embedded Volume registry + `PickVolume` (cube first, then islands).
2) Add `snapInsideIfNearAABB` (copy logic from cube snap; parametrize by extents).
3) Make `ProcessDigRequest` volume‑aware; return `volumeId`/`volumeOrigin` in result.
4) Update `runHoldLoop` to continue in the same volume using `volumeOrigin`.
5) FloatingIslandService: Register/Unregister island volumes on spawn/clear.
6) GridService: Switch to per‑axis clamping derived from `sizeStuds` (Phase 2).
7) (Optional) Client RF for preview volume query.

## Testing Plan
- Unit-ish (server log assertions acceptable in Studio):
  - Dig inside player cube near faces/edges/corners continues to work (snap OK).
  - Dig outside cube but inside a registered island succeeds and writes voxels.
  - Dig outside all volumes is rejected.
  - Hold‑dig continues to drill within the selected island volume.
  - GridService clamps correctly near each face of a rectangular island (no out‑of‑bounds writes).
- Perf checks:
  - Measure write throttle adherence under concurrent miners.
  - Inspect WriteVoxels batch sizes and frame time via existing DigPerformance sections.
- Edge cases:
  - Overlapping volumes (prioritize cube > island); confirm correct target.
  - Island unregistered while digging: next request must fail gracefully.

## Future Work (Not In Scope Now)
- Destructible rocks:
  - Treat as actors with HP and drops; no voxel state. Optionally clear a tiny terrain pocket under the rock upon destruction.
- Rotated volumes:
  - Requires oriented bounds + rotated snap; significantly more math and perf costs. Keep axis‑aligned for now.
- Volume persistence:
  - If islands need persistence, store `state` and `sizeStuds` under island ID; re‑register on load.
- Mining batcher:
  - Per‑tick queue to merge nearby edits across players/volumes; only if profiling shows churn.

## Risks & Mitigations
- Risk: GridService clamp stays global → island OOB writes.
  - Mitigate: Implement Phase 2 per‑axis clamp before enabling island mining.
- Risk: Volume pick conflicts (cube vs island).
  - Mitigate: deterministic priority; log conflicts for tuning.
- Risk: Volume registry leaks.
  - Mitigate: Register/Unregister paths from FloatingIslandService; cleanup on clear/remove.
- Risk: Preview mismatch on client.
  - Mitigate: optional RF to query active volume for exact snap; otherwise rely on server correction.

---
This plan keeps DigService as the orchestrator, GridService as the terrain engine, and adds a small, focused layer for volumes. It unlocks island mining (rectangular prisms) with minimal code churn and a clear path for future optimizations.

## Detailed Specifications (Authoritative)

### Type Definitions (Shared)
- VolumeId: `string` — e.g., `"cube:<userId>"`, `"island:<nanos>:<rand>"`.
- VolumeKind: `"cube" | "island"`.
- VolumePermissions: `{ public: boolean, ownerUserId: number? }`.
- VolumeMeta: `{ themeId: string?, preset: string? }`.
- VolumeState (extends CubeState):
  - `ownerId: number?` (optional for islands)
  - `materialId: string`
  - `chunks: { [ChunkId]: Chunk }`
  - `createdAt: number`
  - `extentsCells: Vector3?` — half‑extents in cells per axis (X/Y/Z). If nil, fall back to cube size logic.
- Volume:
  - `id: VolumeId`
  - `kind: VolumeKind`
  - `origin: CFrame`
  - `sizeStuds: Vector3` (full extents in studs; axis‑aligned)
  - `state: VolumeState`
  - `permissions: VolumePermissions`
  - `meta: VolumeMeta?`

### Constants & Conventions
- Cell size: `CELL_SIZE = GameConfig.Grid.CELL_SIZE_STUDS` (currently 4) — all volume sizes are quantized to multiples of this.
- Quantization helpers:
  - `quantizeStuds(n) = math.floor(n / CELL_SIZE + 0.5) * CELL_SIZE`.
  - `quantizeCFrameToCellCenter(cf)` — keep position on cell centers; rotation must remain identity for volumes.
- Snap tolerances (studs):
  - `FACE_EPS = 2.5`, `EDGE_EPS = max(2.0, CELL_SIZE * 0.45)`, `CORNER_EPS = max(1.5, CELL_SIZE * 0.35)`.

### DigService Additions (Server)
- Data members:
  - `volumesById: { [string]: Volume }`
  - `islandVolumeIds: {VolumeId}` (array) — for iteration/cleanup
  - `playerCubeVolumeId: { [Player]: VolumeId }`
  - Spatial hash (optional, enable if island count > ~128):
    - `hash: { [string]: {VolumeId} }` with `HASH_CELL_STUDS = 256`.
    - `gridKey(x, z) = tostring(math.floor(x / HASH_CELL_STUDS)) .. ":" .. tostring(math.floor(z / HASH_CELL_STUDS))`.

- API (signatures):
  - `function DigService:RegisterVolume(vInit: { id: string?, kind: VolumeKind, origin: CFrame, sizeStuds: Vector3, permissions: VolumePermissions?, meta: VolumeMeta? }): Volume`
    - Ensures axis‑aligned origin (no rotation), quantizes `sizeStuds` and `origin` to cell boundaries.
    - Computes `extentsCells = Vector3.new(sizeStuds.X, sizeStuds.Y, sizeStuds.Z) / CELL_SIZE / 2` (floored per axis).
    - Creates `state = GridService:CreateCubeState(ownerId or 0, materialIdFromTheme(meta) or default)` and injects `state.extentsCells = extentsCells`.
    - Stores in `volumesById`; indexes spatial hash buckets for X/Z footprint.
    - Returns the fully built `Volume` (with generated `id` if missing: `"island:" .. Time.nanos() .. ":" .. math.random(1,1e9)`).

  - `function DigService:UnregisterVolume(id: string): boolean`
    - Removes from `volumesById`, `islandVolumeIds`, and spatial hash buckets; returns true if existed.

  - `local function isInsideNearAABB(worldPos: Vector3, origin: CFrame, half: Vector3, epsFace: number, epsEdge: number, epsCorner: number): (boolean, string, Vector3)`
    - Returns `(ok, hitType, adjusted)`; `hitType` in {"inside","face","edge","corner"} if within tolerance.
    - Implementation mirrors current cube snap but per‑axis using `half`.

  - `function DigService:PickVolume(worldPos: Vector3, player: Player?): Volume?`
    - 1) Prefer the caller’s cube volumeId (if any) and test `isInsideNearAABB`.
    - 2) Query spatial buckets covering `worldPos.XZ`; test candidate island volumes with `isInsideNearAABB` (use smallest outside distance tie‑break).
    - 3) Return the chosen `Volume` or nil.

  - `function DigService:ProcessDigRequest(player: Player, worldPos: Vector3): Types.DigResult`
    - Resolution order:
      1) `vol = PickVolume(worldPos, player)`; if nil → `{ ok=false, reason="Outside mineable volume" }`.
      2) `ok, _, adjusted = isInsideNearAABB(worldPos, vol.origin, vol.sizeStuds/2, FACE_EPS, EDGE_EPS, CORNER_EPS)`; if not ok → reject.
      3) `hasSurface = TerrainSurfaceDetector.CheckCellSurface(adjusted, CELL_SIZE)`; if false → reject `"Invalid terrain"`.
      4) Convert world→cell with `GridMath.worldToCell(adjusted, vol.origin, CELL_SIZE)`.
      5) Call `GridService:ApplyDig(player, vol.origin, vol.state, cx, cy, cz, effectiveStats.size)`.
      6) Return DigResult extended with `volumeId = vol.id`, `volumeOrigin = vol.origin`.

  - Hold‑dig continuity (runHoldLoop): keep `holdState[player].volumeId` and `volumeOrigin` from the last result; use those for stepping deeper with `cellToWorld`.

### GridService Changes (Server)
- Per‑axis clamping inside `ApplyDig`:
  - Compute half‑extents in cells:
    - If `state.extentsCells` exists: `halfX = math.floor(state.extentsCells.X)`, etc.
    - Else: fallback to `half = (GameConfig.Grid.CUBE_SIZE_STUDS / CELL_SIZE) / 2` for all axes.
  - Apply independent bounds:
    - `minX = -halfX`, `maxX = halfX - 1` (same pattern for Y/Z).
  - All subsequent loops remain unchanged.
- No signature change to `ApplyDig`; `WriteCellsToTerrain` remains the same.
- `CreateCubeState(ownerId, materialId)` stays; island states are created via this and extended with `extentsCells` by DigService.

### FloatingIslandService Integration
- On `GenerateIsland`:
  - Compute `origin = CFrame.new(cubePos)` and `sizeStuds = cubeSize` (Vector3).
  - Quantize: `origin = quantizeCFrameToCellCenter(origin)`, `sizeStuds = Vector3.new(quantizeStuds(size.X), ...)`.
  - ID generation: `id = string.format("island:%d:%d", Time.unix(), math.floor(Random.new():NextNumber()*1e9))`.
  - Call `DigService:RegisterVolume({ id=id, kind="island", origin=origin, sizeStuds=sizeStuds, permissions={ public=true }, meta={ themeId=theme, preset=preset } })`.
- On `ClearAllIslands` (or per‑island removal): `DigService:UnregisterVolume(id)`.

### Permissions & Rules
- Initial policy:
  - Cubes: only owner may mine (existing behavior).
  - Islands: public mining (permissions.public = true). Later: allow whitelists or ownership.
- Overlap policy: if both cube and island qualify, pick cube.
- Distance check (optional hardening): reject digs if `|worldPos - player.HRP.Position| > GameConfig.Digging.MAX_RANGE`.

### Anti‑Cheat & Safety
- All validation is server‑side; client preview is cosmetic.
- Snap‑inside avoids rejecting legitimate “overhang” clicks while stopping far‑outside requests.
- Maintain existing cooldowns and throttling; add per‑volume write budgets later if profiling warrants.

### Optional Client UX (Later)
- RF: `QueryVolumeAt(position: Vector3) -> { ok: boolean, id?: string, origin?: CFrame, size?: Vector3 }` for perfect preview snapping.
- Event: none needed; server correction suffices for MVP.

## Testing & Acceptance Criteria (Expanded)
1) Cube mining still works:
   - Face/edge/corner clicks outside exact bounds snap in and succeed.
   - Continuous dig drills down within cube; no out‑of‑bounds writes.
2) Island mining works:
   - Dig within rectangular island bounds succeeds; outside fails.
   - Continuous dig remains in the island across iterations; stops at island floor.
3) Overlap:
   - Position inside both cube and island → cube chosen (verified via logging or temporary telemetry).
4) Clamping:
   - At each prism face, verify clamped cells respect per‑axis half‑extents.
5) Performance:
   - Under 4 concurrent miners, WriteVoxels batches stay within throttle; frame time acceptable.
6) Removal:
   - Unregistering an island while a player is mining it causes next request to reject gracefully.

## Feature Flags & Rollout
- Add `GameConfig.Features.ENABLE_ISLAND_MINING` (default false). Guard volume picking with this flag for safe rollout.
- Logging:
  - `DigService` logs volume picks at debug level: `pick={id, kind}`; upgrade to info during QA.
  - `GridService` logs when using per‑axis extents vs global cube clamp.

## Migration Steps (Checklist)
1) Add Types (Volume, VolumeState) to `shared/MiningGame/Types.lua`.
2) Implement Volume registry in `DigService` with Register/Unregister/Pick.
3) Add `snapInsideIfNearAABB` helper (copy from cube version; parametrize by `half`).
4) Update `ProcessDigRequest` to be volume‑aware and include `volumeId`/`volumeOrigin` in result.
5) Update hold‑dig loop to respect `volumeOrigin` for stepping.
6) Wire `FloatingIslandService` to register/unregister volumes.
7) Modify `GridService:ApplyDig` to clamp per axis using `state.extentsCells` if present.
8) Add `ENABLE_ISLAND_MINING` feature flag and guard usage.
9) Test cases (above); enable extra debug logs.

## Risks & Mitigations (Concrete)
- Grid bounds bug → OOB writes: write assertions when `vx/vy/vz` index is outside arrays; log and early return.
- Volume leaks: periodically audit `volumesById` size; add `Service:Stop()` cleanup to clear volumes.
- Spatial hash misses a nearby volume: add fallback O(n) scan if bucket empty.
- Volume priority feels wrong: add config weight or distance tie‑break rule (nearest center).

## Future Extensions (Not In This Pass)
- Destructible rocks → actor system with HP + loot; optional tiny WriteVoxels under the stump on destruction.
- Rotated volumes → oriented bounds, rotated world↔cell transforms; out of scope due to perf/complexity.
- Volume persistence → DataService keyed by island ID storing chunk bits + extents.
