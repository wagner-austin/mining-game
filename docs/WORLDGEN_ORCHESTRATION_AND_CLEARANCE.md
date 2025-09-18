# World Generation Orchestration and Clearance — Implementation Blueprint

This document defines the authoritative plan for world generation and spawn orchestration in the Mining Game. It supersedes prior concept docs and consolidates practical, incremental improvements with clear rollout steps.

Supersedes: ISLAND_TREE_CLEARANCE_PLAN.md, SPAWN_AND_DECORATION_PLAN.md

## Objectives

- Establish an explicit, deterministic generation order to reduce inter-system conflicts.
- Prevent floating island cubes from intersecting ground trees/rocks while keeping trees visually "under" islands.
- Keep the current modular service architecture (Tree/Rock/Firefly/FloatingIsland services), avoiding a monolithic DecorationService.
- Provide a small set of feature flags and tunables for safe rollout and A/B testing.
- Lay groundwork for future systems (rivers, caves, lava) via a lightweight reservation concept, without forcing a refactor now.

## Current State (As Implemented)

- Service framework: `ServiceContainer` + topological start order (see `server/MiningGame/ServiceManager.lua`).
- World generation services:
  - `WorldGenerationService` spawns ground categories (trees/rocks/fireflies) and ensures terrain base.
  - `TreeGenerationService`, `RockGenerationService`, `FireflyGenerationService` handle category-specific scatter.
  - `FloatingIslandService` spawns floating island cubes, registers volumes, and manages island models and terrain.
- Utilities: `shared/MiningGame/WorldGenUtils.lua` centralizes ground raycasts, keepout logic, folders, day/night phase.
- Player spawn: `SpawnService` + `SpawnOrchestrator` manage character placement timing and handshake.

Observed issue: Islands currently spawn after trees/rocks, causing vertical collisions when island bottoms override canopies.

## Target Orchestration Order

1. Terrain baseline (ensure a ground baseplate exists) — `WorldGenerationService.ensureTerrainBaseplate()`
2. Floating islands (major geometry) — `FloatingIslandService:Start()`
3. Ground decorations — `WorldGenerationService:SpawnDecorations()` calling Tree/Rock/Firefly services
4. Ambient VFX (fireflies already part of 3; additional VFX can follow)
5. Players and NPC agents (outside worldgen; handled by `SpawnService` and character systems)

Rationale: Trees should appear visually under islands, but never intersect them. Major geometry (islands, future rivers/caves) should claim space first; ground scatter adapts around it.

## Island–Tree Clearance (Minimal, Localized Guard)

Implement a per-island vertical clearance check inside `server/MiningGame/FloatingIslandService.lua` (GenerateIsland) immediately before the first `Terrain:FillBlock` call.

Algorithm:
- Use `Workspace:GetPartBoundsInBox(CFrame.new(cubePos), cubeSize, whitelist=BlockDecorations)` to gather overlaps with ground decorations only.
- Compute topmost Y among overlaps. Prefer parts named `LeafWalkSurface` (added by `TreeFactory`) as the canopy reference; fallback to any BasePart top.
- Let `bottomY = cubePos.Y - (cubeSize.Y * 0.5)`.
- If `bottomY < topY + MIN_TREE_GAP_STUDS`, lift island by the quantized amount required to meet the gap.
  - Quantize lifts to `CELL = GameConfig.Grid.CELL_SIZE_STUDS`.
  - If required lift exceeds `MAX_AUTO_LIFT_STUDS`, skip island spawn and log a warning.
- Optionally recheck overlaps once after lifting; if still penetrating geometry (rare), skip spawn (feature-gated).

Tunables (under `GameConfig.FloatingIslands`):
- `ENABLE_TREE_CLEARANCE = true`
- `MIN_TREE_GAP_STUDS = 10`
- `MAX_AUTO_LIFT_STUDS = 96`
- `RECHECK_AFTER_LIFT = false`

Telemetry:
- Info log on lift, including lift amount and measured canopy top.
- Warning on skip due to exceeding cap.
- Optional counters: `islandsLifted`, `islandsSkipped`.

Acceptance:
- After spawn, no island AABB intersects any tree parts in `Workspace/BlockDecorations`.
- Minimum vertical gap equals `MIN_TREE_GAP_STUDS` or more.

## Service Start Order Change

To realize the target order without a heavy refactor, adjust registration order in `server/MiningGame/ServiceManager.lua`:
- Ensure `FloatingIslandService` is registered and started before `WorldGenerationService` (or make WGS depend on islands via the dependency list).
- Keep `Tree/Rock/FireflyGenerationService` registered (optional) and used by WGS.

Notes:
- `WorldGenerationService:Start()` currently calls `safeSpawn()` which only spawns ground categories; islands are already self-contained in `FloatingIslandService:Start()`.
- No need for a monolithic `DecorationService`.

## Config Alignment (Optional, Cosmetic)

- `SpawnService` FRONT_PADDING: The older plan suggested increasing to 36 for better visibility. Today it is `20` (see `server/MiningGame/SpawnService.lua`). Consider bumping to 36 if desired.
- Keep `GameConfig.Decorations` (plural) as the authoritative ground decor config. Prior docs using `GameConfig.Decor` (singular) are deprecated.

## Future-Proofing: Reservation Layer (Lightweight)

When introducing rivers/lava/caves, add a lightweight, optional `ReservationService` that tracks 2D occupancy:

API Sketch:
- `reserve(kind: string, aabb2d, margin) -> id`
- `release(id)`
- `overlaps(aabb2d) -> boolean`

Usage:
- Islands call `reserve` with their XY footprint. Rivers reserve a spline buffer. Cave entrances reserve a keepout ring.
- Tree/Rock spawners call `overlaps` to avoid reserved areas or adapt scale near borders.

Benefits:
- Works with existing services (no refactor). Reserving is advisory; clearance remains the hard guarantee for islands.

## Extensibility: Pets, Underground Cubes, Lava

- Pets: Spawn logic belongs with character lifecycle (e.g., `PetService` reacting to `CharacterAdded`). Not part of worldgen; independent and safe to add.
- Underground cubes/caves: Use existing `CubeVolume`/`DigService` patterns to register volumes; spawn prior to ground decorations; optionally reserve entrances/roofs.
- Lava/rivers: Implement `LiquidGenerationService` to write voxels early, then reserve banks; trees avoid banks or change biome theme near water.

## Rollout Plan

Phase 1 (Low Risk):
- Add the island clearance block (feature-gated) into `GenerateIsland`.
- Add tunables to `GameConfig.FloatingIslands` with conservative defaults.
- Reorder service start: islands before ground decorations.

Phase 2 (Optional Enhancements):
- Consider increasing player spawn FRONT_PADDING to 36.
- Add a tree-side guard (upward raycast to reject/shorten trees under island bottoms). Default off.

Phase 3 (Rivers/Caves):
- Introduce `ReservationService` and integrate reservations into scatter.
- Add new generation services for rivers/caves; start before ground decorations.

## Testing Checklist

- Clearance:
  - Island above no trees: zero lift; no overlaps.
  - Island above short trees: small/no lift; gap satisfied.
  - Island above tall tree: quantized lift; gap satisfied; skip if required lift > cap.
  - Optional recheck path works if enabled.
- Orchestration:
  - On server start, islands appear before trees/rocks.
  - Respawn/clear cycles are idempotent; no duplication.
- Performance:
  - Clearance adds one `GetPartBoundsInBox` per island; spawn counts within targets; no server frame spikes.

## Migration & Doc Status

- Removed: `SPAWN_AND_DECORATION_PLAN.md` (deprecated approach; monolithic DecorationService not adopted).
- Superseded: `ISLAND_TREE_CLEARANCE_PLAN.md` → merged into this document.
- Current authoritative references:
  - `server/MiningGame/ServiceManager.lua` (service order and dependencies)
  - `server/MiningGame/WorldGenerationService.lua` (ground categories, baseplate, logs)
  - `server/MiningGame/FloatingIslandService.lua` (island generation, volume registration)
  - `shared/MiningGame/WorldGenUtils.lua` (rays, keepout, folders, phase)
  - `shared/MiningGame/GameConfig.lua` (tunables)

---
This blueprint documents what we will implement and how it integrates with the existing codebase. It is designed to be incremental, reversible, and production-friendly.

