Title: Inventory — Scroll To Equipped (Minimal Change)

Summary
- Goal: When the player clicks an existing “equipped” control (e.g., the Equipment Bar chips), automatically scroll the Cosmetics grid to the equipped item’s tile so it’s immediately visible.
- Constraints: No new UI elements; no layout changes. Only small, surgical code additions.

Current Behavior
- Inventory renders three grids (Cosmetics, Resources, Consumables) via InventoryTab.
  - ScrollingFrame (grid) is created in `InventoryTab:_sectionCard()` and the Cosmetics grid is stored at `self.cosmeticsGrid`.
    - File: client/MiningGame/UI/Components/InventoryTab.lua:447–487, 569, 1173
  - Item tiles are `TextButton`s named by `item.id` created by ItemTileRenderer and parented directly under the grid.
    - File: client/MiningGame/UI/Components/ItemTileRenderer.lua:38, and placement at InventoryTab.lua:1173
- Equipped map for local player is available as `self._equipped[slot]` inside InventoryTab.
  - Set from profile snapshot/deltas: client/MiningGame/UI/Components/InventoryTab.lua:1233, 1277, 1388, 1404
- InventoryPanel shows an Equipment Bar (chips per slot) and currently only switches to the Cosmetics category on click (no scrolling).
  - File: client/MiningGame/UI/Panels/InventoryPanel.lua:255–316
  - On click today: `if switchCategory then switchCategory("cosmetics", true) end` (line 283)

Target Behavior
- Clicking an Equipment Bar chip scrolls the Cosmetics grid to the tile for that slot’s equipped item (if any), without changing UI layout.
- Optional: A global “Equipped Items” trigger elsewhere can call the same behavior (first equipped slot or a specific slot).

Design (Minimal Additions)
1) InventoryTab: Add a private scroll helper
   - `_scrollToItemInGrid(grid: ScrollingFrame, itemId: string): boolean`
     - Find the tile by name: `local tile = grid:FindFirstChild(itemId)` (only direct children).
     - If not found, return false.
     - Compute vertical delta relative to current viewport:
       - `local dy = tile.AbsolutePosition.Y - grid.AbsolutePosition.Y`
       - New canvas Y: `grid.CanvasPosition = Vector2.new(0, math.max(0, grid.CanvasPosition.Y + dy - margin))`
       - Use a small `margin` (e.g., `UIx.Spacing.SM`) so the row is not flush with the top.
     - Return true when scrolled.

2) InventoryTab: Add a public method
   - `scrollToEquipped(slot?: string)`
     - Ensure Cosmetics section is visible: `self:setCategory('cosmetics')` so the grid is present.
     - Resolve target `itemId`:
       - If `slot` provided: `local id = self._equipped[slot]`.
       - Else: fixed slot order search (e.g., `{ "hand", "head", "back", "aura", "trail" }`) and pick first equipped id.
       - If no id, return.
     - Attempt `_scrollToItemInGrid(self.cosmeticsGrid, id)`.
     - If not found, filters may hide the tile:
       - Clear filters: `self:setFilters('ALL', '')` and rebuild: `self:_updateDisplay()`.
       - Defer the scroll one frame to allow UIGridLayout re-measure:
         - `task.defer(function() _scrollToItemInGrid(...) end)`

3) InventoryPanel: Wire the existing Equipment Bar chips
   - In the chip `onClick` handler (client/MiningGame/UI/Panels/InventoryPanel.lua:281–285):
     - After switching to cosmetics, call `self._invTab:scrollToEquipped(slotId)`.
   - No other UI changes are needed.

Notes & Rationale
- Using `AbsolutePosition` deltas plus `CanvasPosition` focuses the item based on current viewport; this is resilient to automatic layout.
- Grids use `AutomaticCanvasSize = Y` and `UIGridLayout`; tiles are direct children, so `FindFirstChild(itemId)` is robust.
- Filters are cleared only when necessary (tile not found), then we rebuild once and perform a deferred scroll.

Edge Cases
- No item equipped for a slot: `scrollToEquipped(slot)` no-ops.
- Item filtered out: method clears filters and retries once.
- Very small inventories: scroll delta is 0 (no visible change).
- If the tab is inactive and the grid hasn’t been built yet, `scrollToEquipped` calls `_updateDisplay()` prior to scrolling.

Test Plan
1) Equip an item in each cosmetic slot; open Inventory → click each Equipment Bar chip:
   - Inventory is in Cosmetics category.
   - The grid scrolls so the corresponding tile is visible in the viewport.
2) Apply a search filter hiding the equipped item; click the chip:
   - Filters reset to show the item.
   - The grid scrolls to the tile within one frame.
3) Large cosmetics list (requires scroll):
   - Verify precise scrolling brings the tile into view (with slight margin).
4) No item equipped for a slot; click that chip:
   - No scroll; no errors; UI unchanged.

Implementation Footprint (Files)
- client/MiningGame/UI/Components/InventoryTab.lua
  - Add `_scrollToItemInGrid` (private) and `scrollToEquipped` (public).
- client/MiningGame/UI/Panels/InventoryPanel.lua
  - Augment Equipment Bar chip `onClick` handler to call `self._invTab:scrollToEquipped(slotId)` after `switchCategory('cosmetics', true)`.

Acceptance Criteria
- Clicking any Equipment Bar chip scrolls the Cosmetics grid to that slot’s equipped item, with no new UI elements or layout changes.
- If filters/search hide the tile, the method resets filters and scrolls after a single rebuild.
- Behavior is a no-op when the slot has no equipped item.
- No regressions to Inventory filters, category switching, or tile rendering.

Rollout Steps
1) Implement the two small methods in InventoryTab and the single-line call in InventoryPanel.
2) Test in Studio with various inventories, filters, and screen sizes.
3) Commit with a focused message (scope: inventory/ui).

