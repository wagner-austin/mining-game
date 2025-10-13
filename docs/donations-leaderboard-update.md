Donations Leaderboard Update Plan

Overview
- Goal: Make the “Top Donators” leaderboard reflect only Robux spent on the explicit DONATE developer product, not total lifetime Robux nor any gamepass backfill.
- Scope: Server highscores, monetization accounting, type definitions, and a small data migration for existing profiles.

Current Behavior (as of this repo)
- Highscores use total lifetime spend:
  - server/MiningGame/RemoteFns/HighScore.rf.lua:34 — uses `profile.robuxSpentLifetime` for the `"donator"` category.
- Purchases and backfill update totals in one place:
  - server/MiningGame/MonetizationService.lua:152 — increments `profile.robuxSpentLifetime` for all purchases.
  - server/MiningGame/MonetizationService.lua:157 — increments `robuxSpentGamePasses` for gamepasses; `robuxSpentDevProducts` for dev products.
- Gamepass backfill runs on join and adds to totals (not related to donations but explains inflated values):
  - server/MiningGame/MonetizationService.lua:449–485 — verifies ownership and calls `processPurchase(..., "Backfill", ...)` for gamepasses.
- Configured donate product and gamepasses:
  - shared/MiningGame/GameConfig.lua:334 — DONATE product (id = "DONATE", productId = 3411959603, robux = 100)
  - shared/MiningGame/GameConfig.lua:339 — VIP (gamepassId = 1481633877, robux = 1000)
  - shared/MiningGame/GameConfig.lua:341 — BIGGER_DIG (gamepassId = 1481773901, robux = 300)
  - shared/MiningGame/GameConfig.lua:343 — AUTO_DIGGER (gamepassId = 1481997949, robux = 500)

Target Behavior
- The highscores category `"donator"` must show only the sum of Robux spent on the DONATE developer product.
- Gamepass purchases (prompted or backfilled) must not affect donation totals.
- Only actual purchases (receipts) should contribute; there is no backfill for dev products.

Design Decisions
- Introduce a dedicated field `profile.robuxSpentDonations`.
  - Increment it only when a receipt is processed for the DONATE product.
  - Maintain existing totals for `robuxSpentLifetime` and `robuxSpentDevProducts` for compatibility.
- Point the highscores `"donator"` category to `robuxSpentDonations` (not lifetime or dev-products aggregate).
- Provide a migration so existing players retain donation totals:
  - As of shared/MiningGame/GameConfig.lua:332–335, DONATE is the only developer product configured. Therefore, using `robuxSpentDevProducts` to initialize `robuxSpentDonations` is correct and lossless today.

Code Changes
1) Highscores: use donations-only field
   - File: server/MiningGame/RemoteFns/HighScore.rf.lua:34
   - Change:
     - From: `value = tonumber((profile.robuxSpentLifetime or 0)) or 0`
     - To:   `value = tonumber((profile.robuxSpentDonations or 0)) or 0`

2) Types: add `robuxSpentDonations` to PlayerStats
   - File: shared/MiningGame/Types.lua:63–76 (PlayerStats monetization section)
   - Add a nullable number field alongside existing monetization counters:
     - Insert new line after shared/MiningGame/Types.lua:66
       - `robuxSpentDonations: number?,`

3) MonetizationService: increment donations only for DONATE dev product
   - File: server/MiningGame/MonetizationService.lua
   - Location: inside `processPurchase(...)` after the existing per-kind counters
     - Context anchor lines:
       - server/MiningGame/MonetizationService.lua:152 — sets `robuxSpentLifetime`
       - server/MiningGame/MonetizationService.lua:155–157 — increments dev vs gamepass totals
   - Add:
     - For `kind == "DevProduct"`, look up `productIdToData[id]` and if `prod.id == "DONATE"`, then:
       - `profile.robuxSpentDonations = (profile.robuxSpentDonations or 0) + (price or 0)`
   - This uses the same `price` recorded at purchase time (from `getProductPrice(Enum.InfoType.Product, productId)` in `processReceipt`, server/MiningGame/MonetizationService.lua:322), ensuring leaderboard matches what the player was charged at that moment.

4) Data migration: initialize donations from dev-products total (only DONATE exists)
   - File: server/MiningGame/DataService.lua
   - Location: after existing migration/defaults during profile load
     - Context anchor lines:
       - server/MiningGame/DataService.lua:561–597 — existing migration block
   - Add:
     - `profile.robuxSpentDonations = profile.robuxSpentDonations or profile.robuxSpentDevProducts or 0`
   - Rationale: Given shared/MiningGame/GameConfig.lua:332–335 config, all historical dev product spend is donation spend.

Acceptance Criteria
- Joining a fresh profile shows 0 for `Top Donators`.
- Purchasing the DONATE product (GameConfig productId 3411959603) increases the `Top Donators` amount by the product’s price at purchase time.
- Purchasing any gamepass (VIP, BIGGER_DIG, AUTO_DIGGER) does not affect the `Top Donators` board.
- Existing profiles with prior donations display the same totals on the `Top Donators` board after migration.
- Re-processing the same receipt (idempotency) does not double-count donation spend.

Test Plan
Manual tests (Studio/Live):
- Fresh profile
  - Start server, spawn banner with highscores configured for `"donator"` (client/MiningGame/UI/Components/HighScoreBillboard.lua).
  - Confirm `Top Donators` shows 0.
- Donation purchase
  - Trigger purchase of product id `"DONATE"` (shared/MiningGame/GameConfig.lua:334) via RF:
    - server/MiningGame/RemoteFns/Monetization.rf.lua → `PromptPurchase(player, "product", "DONATE")` path.
  - Confirm server logs receipt (server/MiningGame/MonetizationService.lua:305–368) and increments `robuxSpentDonations`.
  - Confirm `Top Donators` updates to the purchase price.
- Gamepass purchase
  - Prompt gamepass purchase for `VIP` or others; complete it.
  - Confirm `Top Donators` remains unchanged.
- Offline receipt path
  - With the player offline, simulate `processReceipt` enqueue by granting a dev product receipt in datastore (or by running a test server where receipt arrives pre-join).
  - On join, `DataService:ConsumePendingGrants` (server/MiningGame/MonetizationService.lua:420–441) processes the grant once, and `processPurchase` increments `robuxSpentDonations` for DONATE only.
- Idempotency
  - Confirm a repeated receiptId does not double-count (guarded by `processedReceiptIds`, server/MiningGame/MonetizationService.lua:144–148).

Edge Cases and Notes
- Price variability: Leaderboard reflects the price at the time of purchase (`getProductPrice` resolves Marketplace price first, then falls back to config if unavailable), matching current system behavior.
- Refunds: Roblox refunds are not surfaced via the same receipt pipeline; donations will not auto-decrement. If we ever need refund handling, it must be designed separately.
- Additional dev products: The increment condition keys off the product’s string `id == "DONATE"`, so adding other dev products will not affect donations.
- Backfill: Only gamepasses are backfilled (server/MiningGame/MonetizationService.lua:449–485). Dev products (including DONATE) are not backfilled, so donations will strictly reflect purchases.

Files to Modify (summary)
- server/MiningGame/RemoteFns/HighScore.rf.lua:34 — use `robuxSpentDonations` for `"donator"`.
- shared/MiningGame/Types.lua: add `robuxSpentDonations: number?` to PlayerStats.
- server/MiningGame/MonetizationService.lua: in `processPurchase`, increment `robuxSpentDonations` only for DONATE dev product.
- server/MiningGame/DataService.lua: migration to initialize `robuxSpentDonations` from `robuxSpentDevProducts`.

Optional (not required for this change)
- Expose donations in `MonetizationService:GetMetrics` for display in MetricsTab (client/MiningGame/UI/Components/MetricsTab.lua).
  - Would add a `donations` field sourced from `profile.robuxSpentDonations`.

Rollback Strategy
- Revert HighScore to use `robuxSpentLifetime` if needed.
- Remove `robuxSpentDonations` increments and the migration line; the additional field being present is harmless and can remain nullable.

Operational Steps
- Implement code changes above.
- Smoke test in Studio (fresh profiles + test purchases + gamepass purchases).
- Deploy; no data wipes required. The migration code will initialize donations for existing profiles on first load post-deploy.
