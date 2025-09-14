# Creature AI (ECS) – Crow MVP Implementation Plan

Owner: AI/Gameplay
Status: Draft for implementation
Scope: Server-side ECS-lite AI for crow, foundational for future animals (bats, rats, etc.)

## Objectives

- Deliver a rock-solid, high-quality crow AI in the mining game using an ECS-lite architecture.
- Preserve the “smart feel” of the ball-game crow: natural spacing, smooth transitions, obstacle-savvy.
- Establish a modular, DI-friendly foundation that scales to more species and higher counts.
- Keep threat/interaction minimal for MVP; focus on Follow, Perch, Patrol, Flee, locomotion, and animations.

## References (Current Codebases)

- Mining game services (DI patterns, event bus, world utils):
  - `server/MiningGame/*` services (e.g., FireflyGenerationService as spawn pattern)
  - `shared/MiningGame/{Logger, Time, GameConfig, ServiceValidator, PCGConfig, EventBus, EventNames, EventContracts, WorldGenUtils}`
- Ball game crow (behavioral patterns to emulate, not copy):
  - State/Hysteresis/Dwell: `server/AI/StateManager.lua`
  - Follow behavior nuances: `server/AI/Behaviors/Follow.lua`
  - Steering/Avoidance: `server/AI/Steering/{Avoidance, Separation}.lua`
  - Tuning/config style: `shared/AI/{CrowTuning.lua, RavenConfig.lua}`

We will not graft code; we will replicate the good behavior via ECS systems and clean configs.

## High-Level Architecture (ECS-lite)

- Entity = creature instance (crow). Data-only components per entity.
- Systems = ordered processors that iterate component arrays on fixed cadences.
- Services = DI-registered singletons that own ECS and provide world queries and spawning.
- Species layer = data/config + thin species module for crow that plugs into ECS.

Update phases per tick:
1) LOD → 2) Sense → 3) Bubble → 4) Evaluate (HFSM + utility) → 5) Command (anchor generation) → 6) Steering → 7) Locomotion → 8) Animation → 9) Debug

## Services (DI, eager construction)

1) CreatureECSService (new)
- Responsibilities:
  - Own entity registry, component arrays, free-list allocators.
  - Schedule systems with deterministic staggering and LOD buckets.
  - Public API: `registerEntity(model, species) -> entityId`, `despawn(entityId)`, `count()`, `setDebug(bool)`.
  - Validate on Start: all systems registered, species registered, required assets present.

2) CrowSpawnService (new)
- Responsibilities:
  - Procedural crow spawning (patterned after `FireflyGenerationService`): area requests, min spacing, player keepout.
  - Safe spawn probes: ground/perch candidates, clearance, island containment (via WorldGenUtils hooks).
  - Calls `CreatureECSService.registerEntity` with `species="crow"` and parents models under a decorations folder.
  - Despawn/hibernate policies; model pooling (phase 2+).

3) WorldQueryService (new)
- Responsibilities:
  - Shared raycasts, overlap queries, ground/ceiling probes, free-space sampling.
  - Pool and reuse `RaycastParams`; keep ignore lists (self, tagged hitboxes) up to date.
  - Budgeted queries; returns compact structs to avoid allocations.

4) DebugDrawService (new)
- Responsibilities:
  - Render gizmos: comfort bubble spheres, goal anchors, steering vectors, ray hits.
  - Toggle by attribute or server setting; rate-limit drawing; auto-cleanup on despawn.

All services are registered in `ServiceManager`/container at server init; no lazy loads. Use `ServiceValidator` for dependency wiring checks.

## Species Registration (Crow)

- SpeciesRegistry (part of ECS service or separate module):
  - Registers `crow` with config pointers and species module.
  - Validates required clips/attributes are present in assets (animation ids, etc.).

- CrowConfig (data-only; lives in `shared/MiningGame/AI/Config/Crow.lua`):
  - Comfort bubble: `r0`, `k_speed`, `k_confined`, `soft/hard/fleeOffsets`, clamps.
  - Follow: `ringR`, `lead`, `jitter`, `idleSpeedThresh`, `switchBase`, `hysteresis`, `clampHold`.
  - Flight: `cruiseAGL`, `minAGL`, `climbRate`, `descentRate`, `enterRampSeconds`.
  - Speeds: ground walk/run, flight normal/fast; turn/accel clamps.
  - Rays: yaw angles, look-ahead scale; cadence per LOD.
  - Animation: intent blend times, velocity thresholds, per-intent speed scaling.

- CrowSpecies module (thin; `shared/MiningGame/AI/Species/Crow.lua`):
  - Provides hooks used by Evaluate/Command/Animation systems (e.g., how to compute ring anchor or flight anchor) based on config.
  - Supplies default LOD thresholds and spawn-time initialization.

## Components (data-only)

Allocate as parallel arrays; index by `entityId`.

- Transform: `{ root:BasePart, pos:Vector3, vel:Vector3, up:Vector3 }`
- LOD: `{ level:"High"|"Med"|"Low"|"Cull", distToPlayer:number }`
- Sensors: `{ nearestPlayer:Player?, playerPos:Vector3?, playerSpeedXZ:number, ground:Vector3?, freeSpace:number, ceilingClear:boolean, rays:{fwd?:RaycastResult, left?:RaycastResult, right?:RaycastResult, up?:RaycastResult} }`
- ComfortBubble: `{ soft:number, hard:number, flee:number, primary:Player?, radiiEMA:number }`
- AIState: `{ state:"Follow"|"Perch"|"Patrol"|"Flee", sub:"Ground"|"Air", dwellUntil:number, switchCDUntil:number, lastSwitchAt:number, rng:Random }`
- GoalAnchor: `{ target:Vector3, mode:"Ground"|"Flight", maxStep:number, updatedAt:number }`
- Command: `{ locomotion:"Ground"|"Flight", speedCap:number, retreat:boolean, weights:{avoid:number, sep:number, bubble:number} }`
- Steering: `{ goal:Vector3, goalDir:Vector3, avoidance:Vector3, separation:Vector3, bubblePush:Vector3, final:Vector3 }`
- Locomotion: `{ ground:{enabled:boolean, nextMoveTo:Vector3?, lastIssuedAt:number}, flight:{enabled:boolean, target:Vector3?, maxVel:number, rampUntil:number}, agl:number }`
- AnimationIntent: `{ intent:"flight"|"flyUp"|"flyDown"|"walk"|"run"|"breathing", lastChangeAt:number }`
- SpeciesCrow: `{ config:any }` (opaque reference to config table)
- Timers: `{ accSense:number, accEval:number, accAnim:number, accRays:number, debug:boolean }`

Notes:
- Keep arrays preallocated to expected max crows; reuse entries via a free-list.
- Avoid allocating per-tick; reuse small fixed tables for rays where possible.

## Systems (order and cadences)

All systems registered in CreatureECSService with deterministic order and fixed cadences. Systems skip entities outside their required components or below the LOD threshold.

1) LODSystem (each frame)
- Compute nearest player distance; set `LOD.level` using species thresholds.
- Update distance-based cadence multipliers for other systems.

2) SenseSystem (High: 0.2–0.3s, Med: 0.5s, Low: 1.0s)
- Using WorldQueryService:
  - Find nearest player with a valid HRP; populate `Sensors.nearestPlayer`, `.playerPos`, `.playerSpeedXZ`.
  - Ground probe below desired XZ point or at current pos (depending on mode) for `Sensors.ground`.
  - Free-space sampling: `GetPartBoundsInRadius` density near entity to estimate confinedness (0..1).
  - Ceiling check via short upward ray.
  - Obstacle rays: forward, ±25° yaw, up; look-ahead scaled by speed (clamped).

3) BubbleSystem (same cadence as Sense)
- Compute per-player radii (MVP):
  - `r = clamp(rMin, rMax, r0 + k_speed * playerSpeedXZ + k_confined * (1 - freeSpace))`
  - Output `soft|hard|flee` via offsets; select primary violator (closest relevant player); EMA-smooth radii.

4) EvaluateSystem (High: 0.25s, Med: 0.5s, Low: 1.0s)
- HFSM + Utility selection with dwell/hysteresis:
  - Interrupt: `Flee` if distance < `flee`.
  - Else score `Follow`, `Perch`, `Patrol`. Use hysteresis and dwell windows.
  - Inside `Follow`: choose `sub=Ground|Air` with sticky gates:
    - Ground when player slow, within [hard, hard+margin], clampHold satisfied, ceiling clear, space ok.
    - Air when player sprinting, distance ≥ `switchToFly = switchToGround + hysteresis`, or repeated block detected.
- Write to `Command` and `GoalAnchor` only (single writer). Set dwell and switch cooldown timers.

5) CommandSystem (same cadence as Evaluate)
- Generate anchors from the chosen state/sub:
  - Ground: place leader point on ring at `max(hard, ringR)`, ahead of player if moving; add small jitter when idle; clamp ≥ hard; limit step size (≤ 8–12 studs) from last anchor.
  - Air: behind/side/height anchor relative to player; orbit when idle; EMA-smooth anchor.
- Set locomotion request and speed cap; throttle `MoveTo` re-issues (no spam unless Δ > 4 studs or > 1.2s elapsed).

6) SteeringSystem (each frame for High LOD; slower for Med)
- Blend: `final = clampTurn(goalDir + wAvoid*avoidance + wSep*separation + wBubble*bubblePush)`.
- Avoidance from obstacle rays (choose clearer side, slight upward bias if no ceiling hit); separation from nearest friend if present.

7) LocomotionSystem (each frame)
- One mover active invariant.
- Ground:
  - If `Command.locomotion==Ground`, ensure flight disabled; zero lateral drift on landing handoff.
  - Issue MoveTo to `GoalAnchor.target` with throttling; cap walk/run speeds; apply retreat run only briefly.
- Flight:
  - If flight requested, enable AlignPosition/Orientation; ramp `MaxVelocity` over `enterRampSeconds` on enter; clamp vertical rate; maintain AGL via ground ray.
  - Apply `flight.target` from Command/Anchor; XZ clamp to ≥ hard bubble edge.
- Mode switches respect `AIState.dwellUntil/switchCDUntil` and safe-to-land/fly gates.

8) AnimationSystem (0.1s)
- Map locomotion state and vertical velocity to intents: `flight`, `flyUp`/`flyDown`, `walk`/`run`, `breathing`.
- Rate-limit intent changes (≥ 0.25s); apply configured blend times; scale playback speed from measured velocity to reduce foot sliding.

9) DebugDrawSystem (0.25–0.5s when enabled)
- Draw soft/hard/flee spheres; anchors; steering vectors; obstacle rays.
- HUD per entity: state, sub-mode, dwell remaining, distXZ, playerSpeed.

## Spawning & Lifecycle

- CrowSpawnService API:
  - `GenerateInArea(opts)` similar to Fireflies: `{bounds or center+size, densityPer100x100, minCount, maxCount, seed, minSpacing, playerKeepoutRadius, parentFolder}`
  - Uses `WorldGenUtils` to avoid players and ensure safe ground/perch; optional island containment check.
  - For each spawn position: clone crow model, tag with species="crow", parent, then `CreatureECSService.registerEntity`.
  - Despawn policy: if `LOD == Cull` for N seconds and far from players, despawn or hibernate; pool for reuse (phase 2).

## Data & Config Locations (proposed)

- `shared/MiningGame/AI/Config/Crow.lua` – crow tunables (bubble, speeds, rays, anim thresholds, LOD distances).
- `shared/MiningGame/AI/Species/Crow.lua` – species helpers (anchor computation, defaults).
- `server/MiningGame/AI/ECS/*` – ECS services, systems, and component arrays.
- `server/MiningGame/AI/Spawn/CrowSpawnService.lua` – crow spawner.
- `server/MiningGame/AI/Debug/DebugDrawService.lua` – gizmos.

## Performance Budget & LOD Targets

- High (within ~50 studs of any player): Sense 0.25s, Evaluate 0.25s, 3–5 rays per think, per-frame Steering/Locomotion, Anim 0.1s.
- Medium (~50–120 studs): Sense/Evaluate 0.5s, 1–2 rays per think, Steering half-rate.
- Low (>120–200 studs): idle/perch only; no obstacle rays; periodic sanity checks.
- Cull (>200–300 studs): paused; consider despawn/hibernate if sustained.
- Deterministic staggering by `entityId % bucketSize` to flatten costs.

## Reliability & Quality Guards

- Mode stability: dwell (≥2.0s) + switch cooldown (≥1.5s) + hysteresis (≥10–12 studs).
- Safe-to-land gate: player slow, within [hard, hard+margin], clampHold time met, ceiling clear, free-space adequate.
- Target hygiene: 2 Hz anchor updates, max step clamp (≤8–12 studs), EMA smoothing, MoveTo throttling.
- One mover active: assert in debug; clean handoffs (zero lateral drift on landing; ramp max velocity on takeoff).
- Error boundaries around each system; fallback to Patrol; rate-limited logs; seeded RNG per entity.

## Debugging & Telemetry

- Gizmos (toggle via attribute or config): bubble spheres, anchors, steering, rays.
- Periodic logs (≤1/sec/entity): `state`, `sub`, `distXZ`, `playerSpeed`, `clampHeld?`, `dwellRemaining`, `raysHit`.
- Metrics collected by ECS service: state flips/min, MoveTo issue rate, path aborts, stuck recoveries, rays/agent/sec, avg think time.

## Acceptance Criteria (POC)

1) Walking near player for 60s in forest/tunnels: no ground↔flight ping-pong; smooth turns; no path thrash.
2) Player stops: crow wanders on ring; maintains hard radius; minimal MoveTo churn.
3) Player sprints away: flight transition in 0.5–1.0s; no “zoom burst”; AGL holds; clean animation blend.
4) Trees/floating islands: no pinwheel; lateral sidestep or flight recovery; minimal stuck recoveries.
5) Performance: 5–10 crows near players at stable FPS; rays and think times within budget; no GC spikes.

## Milestones & Timeline

- M0 – Bootstrap ECS: CreatureECSService, component arrays, DI registration, validation scaffolding.
- M1 – WorldQueryService, LODSystem, SenseSystem (players/ground/free-space/ceiling, basic rays).
- M2 – BubbleSystem (MVP), EvaluateSystem (HFSM with dwell/hysteresis; Follow sub-mode selection).
- M3 – CommandSystem (anchors) + SteeringSystem (avoidance/separation/bubble push).
- M4 – LocomotionSystem (ground+flight handoffs) + AnimationSystem (intent mapping & blends).
- M5 – CrowSpawnService (area spawn/despawn) + DebugDrawSystem; initial tuning passes.
- M6 – Hardening: anti-stuck, island containment hooks; acceptance test runs and profiling.

## Risks & Mitigations

- Ground↔Flight thrash → Strict dwell/cooldowns + safe-to-land/fly gates; acceptance tests.
- Target churn (jerk) → Anchor refresh at 2 Hz, step clamp, EMA smoothing, MoveTo throttling.
- Pathfinding oscillations → Prefer direct MoveTo with short waypoints; lateral sidestep; escalate to flight.
- Multi-player jitter → Primary violator with hysteresis; light weights for others; radii smoothing.
- Sensing cost spikes → Fixed ray budget, pooled params, staggered updates, LOD caps.
- Animation popping → Intent debounce (≥0.25s), proper blend times, speed scaling by measured velocity.
- DI/init order pitfalls → Eager service construction; registry validation; binder idempotency.

## Implementation Checklist

- [ ] Create ECS service scaffolding and DI registration.
- [ ] Define component arrays and free-list allocators.
- [ ] Implement LODSystem and nearest-player distance calc.
- [ ] Implement WorldQueryService with pooled `RaycastParams`.
- [ ] Implement SenseSystem (players/ground/free-space/ceiling + rays).
- [ ] Implement BubbleSystem (MVP formula + EMA + primary violator selection).
- [ ] Implement EvaluateSystem (HFSM + utility; dwell/hysteresis; Follow Ground/Air gates).
- [ ] Implement CommandSystem (ground ring/air anchors; throttled MoveTo commands).
- [ ] Implement SteeringSystem (goal+avoidance+separation+bubble; turn/accel clamps).
- [ ] Implement LocomotionSystem (ground/flight handoffs; velocity ramp; AGL hold).
- [ ] Implement AnimationSystem (intent mapping, blends, speed scaling).
- [ ] Implement DebugDrawSystem; add toggles and minimal HUD.
- [ ] Build CrowSpawnService (safe spawn, spacing, keepout; despawn policy).
- [ ] Tune initial CrowConfig; run acceptance scenarios and profiling.

## Appendix A – Example Config Sketch (Crow)

```lua
return {
  Bubble = {
    r0 = 18, k_speed = 0.25, k_confined = 6.0,
    softOffset = 2, hardOffset = 0, fleeOffset = -6,
    min = 12, max = 40,
  },
  Follow = {
    ringR = 18, lead = 3, jitter = 2,
    idleSpeedThresh = 10,
    switchBase = 20, hysteresis = 12, clampHold = 0.35,
  },
  Flight = { cruiseAGL = 20, minAGL = 6, climbRate = 24, descentRate = 20, enterRampS = 0.4 },
  Speeds = { walk = 10, run = 14, fly = 7, flee = 11, turnClamp = 0.2 },
  Rays = { yaw = 25, minL = 12, maxL = 60, upFactor = 0.6 },
  Anim = { fadeIn = 0.2, fadeOut = 0.3, walkToRun = 8, flyUpVy = 1.5, flyDownVy = -1.5 },
  LOD = { High = 50, Med = 120, Cull = 220 },
}
```

## Appendix B – DI Construction Order

1) WorldQueryService
2) CreatureECSService (alloc arrays, register systems, register species registry)
3) DebugDrawService
4) CrowSpawnService (depends on ECS + WorldQuery)
5) Start phase: validation (species present, assets available), warm-up checks

## Appendix C – Safe-to-Land / Safe-to-Fly Gates

- Land only when: `distXZ in [hard, hard+margin]`, `playerSpeedXZ <= idleThresh`, `|ΔY| <= 2`, `ceilingClear`, `clampHeld >= clampHold`.
- Fly only when: `distXZ >= switchToFly`, or `playerSpeedXZ >= sprintThresh`, or `recoveryNeeded`.

---

This plan focuses on a robust, testable core with measured complexity. It mirrors the successful patterns from the ball-game crow, while adopting an ECS-lite structure suited for the mining game’s service architecture and performance needs.

