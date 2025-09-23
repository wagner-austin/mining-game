# Terrain-Simple Loot Mode

This mode simplifies drops to one resource per terrain/material. It’s ideal for a clean baseline before expanding cosmetics or complex loot tables.

- Config flag: `GameConfig.Loot.MODE = "TERRAIN_SIMPLE"`
- Mapping: `GameConfig.Loot.TERRAIN_RESOURCE_MAP.byMaterialId`
- Drop chance: still governed by `GameConfig.Loot.BASE_DROP_CHANCE`, luck, and any `chanceMult` from compositions/themes.
- Cosmetics: ignored by LootService when in this mode (they remain defined for UI/index).

## Mapping
Edit the mapping in `shared/MiningGame/GameConfig.lua`:

```
TERRAIN_RESOURCE_MAP = {
  byMaterialId = {
    tier1 = "stone",
    tier2 = "sandstone",
    tier3 = "basalt",
    tier4 = "slate",
    tier5 = "glacier_shard",
    tier6 = "lava_rock",
  }
}
```

Cube material ids come from `GameConfig.CubeMaterials` (e.g., `tier1..tier6`). Each maps to a single `ITEMS` id.

## Behavior
- LootService: if a drop roll succeeds, the mapped item is granted for the cell’s cube material.
- LootMath: client calculations reflect that only the mapped item has non-zero probability.

## Expanding later
- Switch back to the original weighted system by setting `MODE = "WEIGHTED_TABLE"`.
- Keep new items or replace them; the weighted system will include all `ITEMS` (and optional cosmetics if enabled).
