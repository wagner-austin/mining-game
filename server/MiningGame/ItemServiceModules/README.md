ItemServiceModules overview

- DropRegistry.lua
  - Owns active drop state, player counters, pickup cooldowns, and hover tweens.
  - Provides helpers: registerDrop, removeDrop, getNearbyDrops, updateDropCountLabel.
  - Invariants: all removals go through removeDrop to keep playerDropCounts correct; hover tweens are cancelled safely.

- Magnet.lua
  - Computes auto-collect entitlement and pickup ranges from config and gamepasses.
  - Exposes: `Magnet:hasAutoCollect(player)` and `Magnet:effectivePickupRange(dropData, player, age, hasAuto, magnetRange)`.

- Collector.lua
  - Handles single-drop collection flows: validations, partial/full pickup, animations, sounds.
  - Also exposes EmitCollected and RareSignals so other modules (e.g., AutoCollector) can reuse feedback logic.

- AutoCollector.lua
  - Periodic aggregation of nearby eligible drops with owner magnet range growth.
  - Uses `Magnet:effectivePickupRange(...)` for per-drop player range and Collector helpers for feedback.

- Spawner.lua
  - Spawns drop models, applies per-dig cap with rarity priority, and schedules despawn.
  - Exposes setAutoCollectFn to delegate oldest-drop cleanup to Collector logic.

- Sweeper.lua
  - Low-frequency safety sweep to grant to owners and remove invalid/expired drops.

Notes
- ItemService.lua orchestrates modules and exposes the public API; no other code should access internal module state directly.
- Feature flags (loot magnet, forced-claim) remain effective; defaults preserved if absent.
