# Workstreams Coordination

Purpose
- Single source of truth for upgrades and cross-cutting tasks.
- Tracks owners, scope, dependencies, decisions, and status across the team.

Roles & Contacts
- Manager: [to be filled by Manager]
  - Name: 
  - Roblox/Studio contact: 
  - Responsibilities: prioritization, approvals, unblocks, sign-off
 - Workers: add yourself with the template below
   - W4 - Worker 4 (Code Agent)
     - Name: Worker 4 - Code Agent (Codex CLI)
     - Focus: Volume-aware digging rollout, Grid/DigEngine integration, RFs (QueryVolumeAt, DigDebug), island volume registration, visual feedback updates, anti-cheat range guard
     - Availability: async, autonomous execution; timezone flexible
     - Notes: uses small, specific commits (1-3 files); always reviews diffs; keeps docs in sync
  - W1 – Worker 1 (AI Assistant)
    - Focus: Cosmetics system (model swap decision, server rendering), multiplayer cosmetic validation, asset audit, rollout plan
    - Availability: async, responds within session
    - Notes: will prepare plans/patches, requests approval before code changes when required

Conventions
- IDs: `WS-###` (e.g., WS-001)
- Status: proposed, in-discovery, planned, in-progress, blocked, review, done, deprecated
- PR/Commit tag: include `[WS-###]` in title
- Docs: keep artifacts under `coordination/` or link to repo paths

Active Workstreams

- WS-010 - Volume-Aware Digging Rollout
  - Owner: W4 (Worker 4)
  - Status: in-progress
  - Scope: Volume registry, snapping/clamping by extents, anti-cheat MAX_RANGE_STUDS, hold/auto loops respect volume
  - Dependencies: GameConfig flags (ENABLE_ISLAND_MINING), Types.extentsCells, GridService.ApplyDig
  - Deliverables: Dig/Processor, Dig/Snapper, Dig/Picker, Dig/Telemetry, Dig/SurfaceSolver; tests and logs

- WS-011 - Grid DigEngine Extraction & Wiring
  - Owner: W4 (Worker 4)
  - Status: done
  - Scope: Extract dig/write operations into Grid/DigEngine and route GridService
  - Dependencies: GridMath, ChunkCodec, Terrain
  - Deliverables: Grid/DigEngine.lua; GridService routed to DigEngine

- WS-012 - Island Volumes Registration & Cleanup
  - Owner: W4 (Worker 4)
  - Status: in-progress
  - Scope: Create/register islands via CubeVolume; tag VolumeId; unregister on clear; register pre-existing on start
  - Dependencies: FloatingIslandService, CubeVolume, VolumeRegistry, WorldGenUtils
  - Deliverables: CubeVolume integration; clear/unregister path; startup registration

- WS-013 - RF Enhancements (Volume.QueryVolumeAt, DigDebug, Observability)
  - Owner: W4 (Worker 4)
  - Status: done
  - Scope: Add QueryVolumeAt for client preview; studio debug RFs for dig telemetry; improve RequestDig logging and RF rate-limit visibility
  - Dependencies: RemoteManager, Result contracts, Service container
  - Deliverables: server/MiningGame/RemoteFns/{Volume.rf.lua,DigDebug.rf.lua,Dig.rf.lua}

- WS-014 - Client Visual Feedback (Volume-Aware)
  - Owner: W4 (Worker 4)
  - Status: done
  - Scope: Track active volume origin/size; update blanket preview alignment; remove legacy variant
  - Dependencies: GameConfig, GridMath
  - Deliverables: shared/MiningGame/DigVisualFeedback.lua; removal of DigVisualFeedback_RaycastEnhanced.lua

- WS-015 - Terrain Surface Detection Reliability
  - Owner: W4 (Worker 4)
  - Status: done
  - Scope: Relax exposure checks (air-ahead), simple presence fallback, targeted debug logging
  - Dependencies: TerrainSurfaceDetector, Logger
  - Deliverables: shared/MiningGame/TerrainSurfaceDetector.lua updates
- WS-001 – Model Swap Decision & Implementation
  - Owner: W1 (Worker 1)
  - Status: in-discovery
  - Scope: Verify current ModelSwap functionality; either implement server-side rendering (HumanoidDescription/Accessories) or remove feature and references
  - Dependencies: ReplicatedStorage.MiningGame.Assets costume availability; InventoryService events; ServiceManager wiring
  - Deliverables: findings summary, recommended approach, implementation plan (server renderer or removal list)

- WS-002 – Multiplayer Cosmetics Validation & Asset Audit
  - Owner: W1 (Worker 1)
  - Status: planned
  - Scope: Validate regular cosmetics across clients; enumerate missing/incomplete assets; propose fallback/placeholder strategy
  - Dependencies: Asset library presence; CosmeticDefinitions mappings
  - Deliverables: validation checklist, asset gap report, remediation plan

Backlog (Candidates)
- WS-003 – Asset Library Organization for Cosmetics (naming, folders, preloads)
- WS-004 – Cosmetic QA Harness (test cases for equip/unequip/race conditions)
- WS-005 – Performance pass for client renderers (preload, weld/motor patterns)

Decision Log
- Template: `YYYY-MM-DD – [WS-###] – decision – rationale – approver`
- 2025-09-14 – [WS-001] – Initiated discovery – Establish baseline and options – W1

Risks & Constraints
- Missing costume assets may limit ModelSwap viability until added
- Server-authoritative rendering for model swaps needs careful token/versioning to avoid race conditions
- Player experience: avoid mid-session visual pops when re-layering after model swap changes

Meeting & Cadence
- Standup cadence: [Manager to define]
- Review cadence: [Manager to define] (suggest weekly feature review)
- Async updates: Post notes in this doc under the relevant WS entry

How To Contribute
- Manager
  - Add/approve WS items, set Owner, Status, and priority
  - Add decisions with approver initials in Decision Log
- Workers
  - Add yourself to Roles & Contacts
  - For each WS you own, keep: Status, Scope, Dependencies, Deliverables up to date
  - Tag PRs/commits with `[WS-###]` and link back here

Definitions
- Model Swap: Character-wide appearance changes via HumanoidDescription or accessory bundles
- Regular Cosmetics: Visuals in slots head, back, aura, trail, pickaxeSkin

Change Log
- 2025-09-14 - Added Worker 4 and workstreams WS-010..WS-015 - W4
- 2025-09-14 – Created coordinating document and seeded WS-001/WS-002 – W1
# Mining Game – Upgrade & Monetization Workstreams

Purpose: Coordinate contributors and track work to ship upgrades and a coins‑first shop flow (cosmetics purchasable with coins, unified purchase entry point).

This document is the shared source of truth for roles, scope, and work plans. The manager and all workers should add/maintain their sections below.

**Participants**
- Manager: [Add name/handle] — Responsibilities: scope, priorities, approvals, release gates.
- Worker 1: [Add name/handle] — Responsibilities: [Add focus area]
- Worker 2: Codex Agent “Quartz” (this doc’s author) — Responsibilities: server RFs, pricing rules, Inventory/Currency integration, Shop UI wiring, docs.

**Scope (Phase 1)**
- Coins‑first purchasing for cosmetics via server RF (no Robux required).
- Optional catalog endpoint to serve item/price data to clients.
- Shop tab in Settings panel listing cosmetics with affordability + purchase UX.
- Keep existing Robux products (boosts, coin packs) as‑is.
- Documentation and basic telemetry; light QA checklist.

Out of scope (Phase 1): bundles, dynamic sales, gifting, trading, entitlement revocation, refund flows.

**Workstreams**
- WS‑1 Server RF: PurchaseItem (coins)
  - Owner: Quartz
  - Status: Not Started
  - Deliverables: `RemoteFns/Shop.rf.lua` with `PurchaseItem(itemId, quantity?)`, validation, rate limiting, `INSUFFICIENT_FUNDS`/`ITEM_NOT_FOUND` errors, emits notifications, saves.
  - DoD: Purchases succeed/fail correctly; coins deducted; inventory updated; events emitted; tests via manual calls.

- WS‑2 Catalog: GetShopCatalog (optional)
  - Owner: Quartz
  - Status: Not Started
  - Deliverables: Server‑auth prices for cosmetics (derived from definitions or config) with filtering by category/rarity; caches if needed.
  - DoD: Client can render a full catalog without hardcoding prices.

- WS‑3 Pricing Rules
  - Owner: Manager (decision), Quartz (impl)
  - Status: Decision Needed
  - Options: (A) Use `CosmeticDefinitions.ITEMS[id].value` as coin price; (B) Add `GameConfig.Shop` with per‑rarity baselines + overrides.
  - DoD: Documented choice; configured on server; reflected by catalog.

- WS‑4 Shop UI (Settings > Shop tab)
  - Owner: Worker 1
  - Status: Not Started
  - Deliverables: `ShopTab.lua` component; lists cosmetics by category/rarity; shows coin prices; button states for affordability; calls `PurchaseItem` RF; handles success/error.
  - DoD: Works in Studio; responsive; matches theme; integrated into `SettingsPanel` via feature flag.

- WS‑5 Feature Flags & Integration
  - Owner: Worker 1
  - Status: Not Started
  - Deliverables: `GameConfig.Features.SHOW_SHOP_TAB` toggle; wire panel tab enablement; ensure cosmetics feature flag respected server‑side.
  - DoD: Toggling flag shows/hides Shop; server RF returns `NOT_AVAILABLE` when disabled.

- WS‑6 Telemetry & Rate Limits
  - Owner: Quartz
  - Status: Not Started
  - Deliverables: Structured log events (e.g., `item_purchase_coin`); RF rate limit ~0.2s; basic abuse safeguards (quantity bounds).
  - DoD: Events visible in logs; rate limit enforced.

- WS‑7 Docs & Examples
  - Owner: Quartz
  - Status: Not Started
  - Deliverables: Update `docs/API_REMOTE_FUNCTIONS.md` (Shop section), error codes, usage snippets; add best‑practice sample in `API_BEST_PRACTICES.md`.
  - DoD: Devs can consume RFs without reading code.

**Sequencing & Milestones**
- M1: Pricing decision (WS‑3) — Manager sign‑off.
- M2: Server RF (+ optional catalog) ready (WS‑1, WS‑2).
- M3: Shop UI integrated and feature‑flagged (WS‑4, WS‑5).
- M4: Telemetry, docs, QA pass (WS‑6, WS‑7).

Target: Ship Phase 1 to test place after M4 passes basic QA in Studio.

**Definition of Done (Global)**
- Feature‑flagged where relevant.
- Server validation, rate limiting, and error codes in place.
- Emits `currency.changed`, `inventory.delta`/`inventory.changed`, and optional notification events.
- Docs updated; minimal QA checklist executed; no regressions to Upgrades/Inventory.

**Testing Plan**
- Studio manual tests: purchase success, insufficient funds, disabled feature flag, invalid item IDs, quantity bounds.
- UI: Shop tab affordability states; success/error toasts.
- Data integrity: coins never negative; inventory increments; save queue triggered.

**Risks & Mitigations**
- Incorrect pricing source — Resolve early via WS‑3 decision; guard behind feature flag.
- Duplicate purchases spam — Rate limit RF; debounce UI; cap quantity.
- Catalog drift — Prefer server‑auth catalog; add TTL caching if needed.

**Branching & PR Conventions**
- Branch names: `feat/shop-rf`, `feat/shop-ui`, `chore/docs-shop`, etc.
- Small, reviewable PRs; include brief test notes; link to WS IDs.

**Decision Log**
- 2025‑MM‑DD — Pricing source: [TBD]
- 2025‑MM‑DD — Catalog endpoint: [TBD]

**Contact / Updates**
- Standups: As needed in PR threads or this doc.
- Owners update status bullets under each WS; Manager maintains milestones.
**Mining Game — Upgrade Workstreams**

- Purpose: Single coordination doc for upgrades across items, cosmetics, and movement effects.
- Owners: Manager + Workers (add yourselves below).

**People**
- Manager: [add name/handle], timezone, contact
- Worker 1: [add]
- Worker 2: [add]
- Worker 3: Codex Assistant ("Worker 3"), PT, contact: this thread

**Scope**
- Item system maintainability and theming
- Base item archetypes with modifiers (cosmetics + gear)
- Equipment-driven effects/boosts (speed, jump, size, luck, flight)
- Cosmetic behaviors (e.g., flap-on-jump wings)
- UI/Inventory sync and rollout safety

**Workstreams**
- WS1: ItemService Cleanup & Drop View Layer
  - Goal: Keep ItemService focused on rules/state; move visuals to factory.
  - Deliverables: DropModelFactory parity, config-driven visuals by rarity/type.
  - Status: Drafted approach; pending manager approval.

- WS2: Themed Items & Archetypes
  - Goal: Define base classes (e.g., Aura, Trail, Wings, PickaxeSkin) + modifiers (theme, rarity, tints).
  - Deliverables: Registry of templates, theme palette hooks, generation helpers.
  - Status: Design required.

- WS3: Equipment Effects & Boosts
  - Goal: Server-authoritative buffs via CharacterStateManager; clean equip/unequip wiring.
  - Effects: speed, jump, size, luck, flight (new), cosmetic-only flags.
  - Deliverables: Effect IDs, durations/stacking rules, server->client sync, feature flags.

- WS4: Wings “Flap-On-Jump” Animation
  - Goal: Cosmetic renderer subscribes to jump/land and plays flapping.
  - Deliverables: Back-slot renderer update, perf-safe connections, cleanup.

- WS5: UI/Inventory Integration
  - Goal: Present equipment/boost state clearly; ensure deltas and snapshots remain stable.
  - Deliverables: Inventory tab tweaks, notifications, accessibility checks.

- WS6: QA, Perf, Rollout
  - Goal: Validate behavior/perf on low-end clients; staged rollout.
  - Deliverables: Test checklist, perf metrics, feature flags, fallback paths.

**Milestones (TBD dates by manager)**
- M1: Approve WS plan and ownership
- M2: ItemService view extraction parity proven in playtest
- M3: Archetype registry + sample themed items
- M4: Effects/boosts server integration (no-ops gated by flags)
- M5: Wings flap-on-jump shipped behind flag
- M6: UI polish + docs

**Decisions & Notes**
- [ ] Use feature flags for new effects (flight/flap) — names: `COSMETIC_FLAP_ENABLED`, `FLIGHT_EFFECT_ENABLED`.
- [ ] Keep cosmetics client-side visuals; effects live server-side in CharacterStateManager.
- [ ] Rare drop announcements unchanged (EPIC+/LEGENDARY/MYTHIC).

**PR & Change Management**
- Small, focused PRs per workstream step; include before/after clips or screenshots.
- Maintain behavior parity until a decision explicitly approves changes.
- Add toggles in `GameConfig.Features`; default off until greenlit.

**Risks**
- Visual churn/regressions in drop models — mitigate with parity checklist.
- Client perf from added effects/animations — mitigate with quality gates and LOD.
- Scope creep in archetypes — mitigate with minimal viable templates first.

**Backlog (unordered)**
- Define flight effect semantics (vertical control? stamina? cosmetic-only hover?).
- Quality-based VFX limits for low settings.
- Theme-driven drop visuals (palette → neon/particles/tint).
- Unit-style tests for equip/unequip events to renderers.

**Next Actions**
- Manager: Confirm/assign owners per WS, set dates, add comms cadence.
- Workers: Add your names, availability, and preferred focus areas.
- Worker 3 (Codex): Prepare parity checklist for WS1 and draft design notes for WS2–WS4.
