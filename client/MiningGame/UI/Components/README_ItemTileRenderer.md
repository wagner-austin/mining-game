Item Tile Renderer

Overview
- Shared helper for rendering item tiles consistently across tabs (Inventory, Item Index, future panels).
- Centralizes visuals: background, corner radius, rarity stroke, emoji/icon symbol, rarity-colored name, count badge, equipped overlay, and optional rarity effects.

Import
```lua
local Renderer = require(script.Parent:WaitForChild("ItemTileRenderer"))
```

API
- `Renderer.create(opts) -> { button: TextButton, helpers: Helpers }`
  - `opts.item: table` – normalized item (from ItemDefinitions)
  - `opts.parent: Instance?` – optional parent (you can parent later)
  - `opts.sizeMode: "grid" | "fixed"` – grid lets UIGridLayout control size; fixed uses `fixedSize`
  - `opts.fixedSize: UDim2?` – required if `sizeMode == "fixed"`
  - `opts.backgroundTransparency: number?` – default 0.1
  - `opts.rarityEffects: boolean?` – if true, auto-applies rarity effects to the symbol

- Helpers on the returned object:
  - `helpers.addSymbol(item) -> TextLabel`
    - Renders an emoji/icon for the item; color is set using rarity color when available.
    - Data-driven icons are supported (preferred in order): `item.icon`, `item.meta.icon`, then fallback mapping by type/slot/id.
  - `helpers.addNameLabel(text, { useRarityColor: boolean?, item: any? }) -> TextLabel`
    - Renders the item name. If `useRarityColor` and `item` are provided, applies rarity color.
  - `helpers.addCountBadge(count) -> TextLabel?`
    - Renders a small badge for stack counts (>1). Returns nil if not rendered.
  - `helpers.showEquippedOverlay() -> TextLabel`
    - Renders a small "EQUIPPED" overlay centered in the tile.
  - `helpers.applyRarityEffects(target: TextLabel, item)`
    - Applies rarity-specific animations: MYTHIC shimmer + pulse, LEGENDARY pulse, EPIC shimmer.
    - Not needed when `opts.rarityEffects = true` (auto-applied to the symbol).

Usage Example (Inventory/Index style)
```lua
local tile = Renderer.create({ item = item, sizeMode = "grid", rarityEffects = true })
local button = tile.button
tile.helpers.addSymbol(item) -- symbol + rarity color (+ effects when enabled)
tile.helpers.addNameLabel(item.name or item.id, { useRarityColor = true, item = item })
tile.helpers.addCountBadge(count)
if isEquipped then tile.helpers.showEquippedOverlay() end
-- Parent button to the desired UIGridLayout container
button.Parent = grid
```

Data Source
- Always use `shared/MiningGame/ItemDefinitions.lua` for item data in UI.
- Do not read from `GameConfig.Loot.ITEMS` or `CosmeticDefinitions` directly in tabs.

Notes
- Hover styling and rarity stroke are applied in the renderer; avoid duplicating per-tab.
- Prefer data-driven icons by adding `icon` to items (directly or under `item.meta.icon`).

