# Floating Island–Tree Clearance Plan

This document proposes a minimal, localized change to prevent floating islands from intersecting with ground trees while keeping current generation services intact and performance-friendly.

## Goals
- Guarantee a minimum vertical gap between an island’s bottom face and the tallest overlapping tree part.
- Avoid refactoring generators or adding a global state machine.
- Keep the logic contained within `FloatingIslandService:GenerateIsland`.
- Provide deterministic, quantized adjustments that preserve terrain grid alignment.

## Scope & Assumptions
- Trees live under `Workspace/BlockDecorations` and are anchored (procedural blocky trees spawned via `TreeFactory`).
- Islands are created in `server/MiningGame/FloatingIslandService.lua` inside `GenerateIsland` with an invisible `Anchor` part sized to the island volume; terrain is written via `Terrain:FillBlock`.
- Terrain cell size is `GameConfig.Grid.CELL_SIZE_STUDS` (currently 4). All position/size adjustments should be quantized to this size.
- We do not change spawn order or global generation orchestration in this phase.

## Configuration
Add tunables (either in `GameConfig.FloatingIslands` or as module-local constants guarded by a feature flag):
- `ENABLE_TREE_CLEARANCE = true`
- `MIN_TREE_GAP_STUDS = 10` (suggest 8–12)
- `MAX_AUTO_LIFT_STUDS = 96` (suggest 64–128)
- `RECHECK_AFTER_LIFT = false` (optional: run one overlap re-check after lifting)

Notes:
- Use `CELL = GameConfig.Grid.CELL_SIZE_STUDS` for quantization (`lift = ceil(needed/CELL)*CELL`).
- If `ENABLE_TREE_CLEARANCE` is false, skip the check and preserve current behavior.
- If adding tunables to `GameConfig`, prefer keeping defaults conservative and guard behavior with the feature flag.

## Algorithm (Single-Pass, Per-Island)
Place this block in `server/MiningGame/FloatingIslandService.lua` inside `GenerateIsland`, immediately before the initial `Terrain:FillBlock` call:

1) Define the initial island AABB
- `anchorCf = CFrame.new(cubePos)`
- `anchorSize = cubeSize`

2) Query overlaps against decorations only (oriented box)
- `local deco = WorldGenUtils.getDecorationFolder()`
- `local p = OverlapParams.new()`
- `p.FilterType = Enum.RaycastFilterType.Whitelist`
- `p.FilterDescendantsInstances = { deco }`
- `local parts = workspace:GetPartBoundsInBox(anchorCf, anchorSize, p)`
  - Note: `GetPartBoundsInBox` uses an oriented box defined by `CFrame` + `Size`, which matches the island shape. We only need a single call; no iterative stepping.

3) Compute tallest overlap (`maxTreeTopY`)
- Prefer parts named `"LeafWalkSurface"` (added by `TreeFactory` at canopy top) or parts tagged with `"BlockTree"`/`"WalkSurface"` if available.
- Fallback: use any overlapping `BasePart` top (`topY = part.Position.Y + part.Size.Y/2`).
- Keep both a “preferred max” (leaf surfaces only) and a “general max”; use preferred if any exist.

4) Enforce minimum clearance
- `islandBottomY = cubePos.Y - cubeSize.Y/2`
- If `islandBottomY < maxTreeTopY + MIN_TREE_GAP_STUDS`:
 - `needed = (maxTreeTopY + MIN_TREE_GAP_STUDS) - islandBottomY`
  - `lift = math.ceil(needed / CELL) * CELL`
  - If `lift > MAX_AUTO_LIFT_STUDS`: skip spawn (return false; log a warning)
  - Else: raise `cubePos = cubePos + Vector3.new(0, lift, 0)` and re-quantize to `CELL`

5) Optional re-check (conservative)
- Re-run step (2) once after lifting; if still overlapping (rare), skip spawn.

6) Proceed with island creation
- Call `Terrain:FillBlock` with the (possibly lifted) `cubePos` and continue existing flow (mixed materials, model creation, volume registration, tagging).

### Pseudocode (Lua-like)
```
local CELL = GameConfig.Grid.CELL_SIZE_STUDS
local GAP  = (GameConfig.FloatingIslands and GameConfig.FloatingIslands.MIN_TREE_GAP_STUDS) or 10
local CAP  = (GameConfig.FloatingIslands and GameConfig.FloatingIslands.MAX_AUTO_LIFT_STUDS) or 96

local function quantize(n)
    return math.floor(n / CELL + 0.5) * CELL
end

local function adjustForTreeClearance(cubePos: Vector3, cubeSize: Vector3)
    local features = GameConfig.Features or {}
    if not features.ENABLE_ISLAND_MINING then return cubePos, "DISABLED" end
    local cfg = GameConfig.FloatingIslands or {}
    if cfg.ENABLE_TREE_CLEARANCE == false then return cubePos, "BYPASS" end

    local deco = WorldGenUtils.getDecorationFolder()
    if not deco then return cubePos, "NO_DECO" end

    local p = OverlapParams.new()
    p.FilterType = Enum.RaycastFilterType.Whitelist
    p.FilterDescendantsInstances = { deco }

    local parts = workspace:GetPartBoundsInBox(CFrame.new(cubePos), cubeSize, p)
    if not parts or #parts == 0 then return cubePos, "NO_OVERLAP" end

    local preferredMax, generalMax = -math.huge, -math.huge
    for _, part in ipairs(parts) do
        local topY = part.Position.Y + part.Size.Y * 0.5
        if part.Name == "LeafWalkSurface" then
            if topY > preferredMax then preferredMax = topY end
        end
        if topY > generalMax then generalMax = topY end
    end
    local maxTopY = (preferredMax > -math.huge) and preferredMax or generalMax
    local bottomY = cubePos.Y - (cubeSize.Y * 0.5)
    local needed = (maxTopY + GAP) - bottomY
    if needed <= 0 then return cubePos, "OK" end

    local lift = math.ceil(needed / CELL) * CELL
    if lift > CAP then return nil, "EXCEEDS_CAP", lift end

    local newPos = Vector3.new(cubePos.X, cubePos.Y + lift, cubePos.Z)
    newPos = Vector3.new(quantize(newPos.X), quantize(newPos.Y), quantize(newPos.Z))

    if (GameConfig.FloatingIslands and GameConfig.FloatingIslands.RECHECK_AFTER_LIFT) then
        local parts2 = workspace:GetPartBoundsInBox(CFrame.new(newPos), cubeSize, p)
        -- Optional: early exit if still overlapping over leaf surface tops
        -- If still overlapping at/above gap, allow (the lift achieved the intended gap)
        -- If overlap implies penetrating geometry, skip spawn to be safe
    end

    return newPos, "LIFTED", lift
end
```

## Logging & Telemetry
- Info log on lift: amount, original bottom, `maxTreeTopY`, final Y.
- Warn on skip due to exceeding `MAX_AUTO_LIFT_STUDS`.
- Optional counters (for QA): islandsLifted, islandsSkipped.

Suggested messages:
- `"Island clearance: lifted=%d studs bottomY=%.1f maxTreeTopY=%.1f gap=%.1f"`
- `"Island clearance: skipped requiredLift=%d > cap=%d at pos=%s"`

## Edge Cases
- No `BlockDecorations` folder or no overlaps: no lift.
- Extremely tall tree beneath island: lift exceeds cap → island skipped.
- Non-tree decorations in `BlockDecorations`: included (conservative). Can refine by filtering parts by parent/tag (`BlockTree`, `LeafWalkSurface`) if needed.
- Manual tree spawns after island placement can still cause later overlaps; this plan targets prevention at island creation time. A cleanup pass is an optional future enhancement.

## Performance
- One `GetPartBoundsInBox` per island plus a simple loop over overlaps.
- With typical island counts (3–12), impact is negligible.

Complexity:
- Overlap query: O(1) per island (engine-side broadphase + narrowphase).
- Loop: O(k) where k = overlapped parts (usually low for sparse canopies).
- No allocations beyond temporary arrays returned by the engine.

## Testing Checklist
- Island above no trees: zero lift; no overlap.
- Island above small trees: small/no lift; gap satisfied.
- Island above tall tree: quantized lift; gap satisfied; no player clipping when climbing.
- Extreme tall tree: island skipped with warning.
- Overlap re-check (if enabled): resolves or skips.
- Quantization verified: positions remain multiples of `CELL`.

Studio test steps:
- Enable `ENABLE_ISLAND_MINING` and `ENABLE_TREE_CLEARANCE`.
- Use `FloatingIsland.rf.Debug_SpawnIsland` to spawn at a position above a dense tree area; verify lift in logs.
- Toggle `MAX_AUTO_LIFT_STUDS` low to force skips; verify warnings and no terrain fill.
- Verify `LeafWalkSurface` acts as canopy reference; remove it in one tree to confirm fallback uses general top.

## Acceptance Criteria
- After spawn, no island AABB intersects any tree parts in `BlockDecorations`.
- A minimum vertical gap of `MIN_TREE_GAP_STUDS` is maintained between island bottoms and tallest overlapping canopy/top.
- No noticeable performance degradation during island generation.

## Future Enhancements (Optional)
- Tree-side guard: before placing a tree, upward raycast; if an island footprint exists within `MIN_TREE_GAP_STUDS`, reject or shorten/scale the tree.
- Spawn order tweak: spawn islands first, then trees with island keep-out footprints.
- Retry logic: if an island is skipped due to cap, retry with slight XY jitter (bounded attempts) to hit target counts.

### Optional: Strict Cleanup Mode
- Policy: if overlaps still occur post-lift (e.g., due to late tree spawns), remove overlapping tree parts inside the island AABB.
- Implementation: after `FillBlock`, call `GetPartBoundsInBox` again and `:Destroy()` overlapping parts or re-parent to a cleanup folder.
- Disabled by default to preserve ground decorations; only enable if art direction demands strict separation.
