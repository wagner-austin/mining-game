# WS-021 — Shop RemoteFunctions Spec (Coins + Cosmetics)

Owner: W3 (Backend RF/Catalog)
Flags: `SHOP_ENABLED` (server RF gate), `SHOW_SHOP_TAB` (UI visibility)
Rate Limit: 0.2s per RF call

## Goals
- Server‑authoritative catalog for cosmetics purchasable with coins.
- Safe purchase path: affordability, atomic deduct + grant, persistence, UI events.
- Auto‑equip on purchase when the target slot is empty.

## Non‑Goals (MVP)
- Gem purchases, bundles, discounts, rotation windows.
- ModelSwap items; hidden/non‑purchasable cosmetics.

---

## GetShopCatalog(category?, rarity?)
Returns a filtered, sorted view of purchasable cosmetics.

Feature gates: requires `SHOP_ENABLED`.

Request
```
{
  category?: "aura" | "trail" | "back" | "head" | "pickaxeSkin",
  rarity?:   "COMMON" | "UNCOMMON" | "RARE" | "EPIC" | "LEGENDARY" | "MYTHIC"
}
```

Behavior
- Source items from `shared/MiningGame/CosmeticDefinitions.lua`.
- Exclude `slot == "modelSwap"` and any explicitly non‑purchasable items (future field).
- Compute `ownedCount` from player inventory.
- Sorting within the result:
  1) notOwned first, 2) rarity rank (MYTHIC→COMMON), 3) price (value) ascending, 4) name ascending.

Response
```
{
  ok: boolean,
  success: boolean,
  items?: Array<{
    id: string,
    name: string,
    slot: string,
    rarity: string,
    price: number,          // from CosmeticDefinitions.ITEMS[id].value
    owned: boolean,
    ownedCount: number,
    purchasable: boolean,
    reason?: string,        // if not purchasable
    effect?: string,
    colorHex?: string,      // optional, for UI tint
    animates?: boolean,
    tags?: string[]
  }>,
  error?: string            // INVALID_INPUT
}
```

Errors
- `INVALID_INPUT` (bad filters)

---

## PurchaseItem(itemId: string, quantity?: number = 1)
Purchases a cosmetic with coins and grants it to the player.

Feature gates: requires `SHOP_ENABLED`.

Validation
- `itemId` non‑empty string.
- Item exists in `CosmeticDefinitions.ITEMS`.
- Item `slot ~= "modelSwap"` and is purchasable.
- `quantity` positive integer, small cap (e.g., <= 10).
- `price = value * quantity`, must pass `CurrencyService.canAfford`.

Behavior
- Atomic flow (pseudocode):
  1) if not canAfford: fail `INSUFFICIENT_FUNDS`.
  2) CurrencyService.add(player, "coins", -price).
  3) InventoryService:AddItem(player, itemId, quantity).
  4) If the item’s equipment slot is empty, auto‑equip via `InventoryService.EquipItem` (single equip, ignore quantity > 1 for equip).
  5) DataService:QueueSave(player).
  6) Emit UI events (Currency, Inventory, Equipment if equipped, Notification).

Response
```
{
  ok: boolean,
  success: boolean,
  itemId?: string,
  quantity?: number,
  coinsSpent?: number,
  equipped?: boolean,        // true if auto‑equipped
  equipSuggested?: boolean,  // true if slot occupied
  error?: string             // one of error codes below
}
```

Error Codes
- `INVALID_INPUT` — bad args
- `ITEM_NOT_FOUND` — id not in catalog
- `NOT_AVAILABLE` — not purchasable (disabled/modelSwap/etc.)
- `INSUFFICIENT_FUNDS` — affordability failed
- `PURCHASE_FAILED` — unexpected failure during grant/equip

Events (emitted elsewhere in services)
- `CURRENCY_CHANGED` via `CurrencyService.add`
- `INVENTORY_DELTA` / `INVENTORY_CHANGED` via `InventoryService`
- `EQUIPMENT_CHANGED` if auto‑equip succeeded
- `NOTIFICATION_PUSH` success/failure toast

Examples
```lua
-- GetShopCatalog()
{
  ok = true,
  success = true,
  items = {
    { id = "aura_fire", name = "Fire Aura", slot = "aura", rarity = "RARE", price = 100, owned = false, ownedCount = 0, purchasable = true, effect = "fire" },
    { id = "back_angel",    name = "Angel Wings",   slot = "back", rarity = "EPIC", price = 500, owned = true,  ownedCount = 1, purchasable = true, animates = true },
  }
}

-- PurchaseItem("aura_fire") success
{ ok = true, success = true, itemId = "aura_fire", quantity = 1, coinsSpent = 100, equipped = false, equipSuggested = true }

-- PurchaseItem("back_angel") success w/ auto‑equip (slot empty)
{ ok = true, success = true, itemId = "back_angel", quantity = 1, coinsSpent = 500, equipped = true, equipSuggested = false }

-- PurchaseItem("aura_fire") insufficient funds
{ ok = true, success = false, error = "INSUFFICIENT_FUNDS" }
```

Security & Perf Notes
- Never trust client price; server reads from definitions.
- Guard with feature flags and rate limits.
- Validate all inputs via `SchemaValidators` (string/int bounds).
- Keep responses lean; defer heavy preview data to UI side.
