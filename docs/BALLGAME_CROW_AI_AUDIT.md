# Ball Game Crow AI Audit — Animations, Assets, Physics, Movement

Purpose: capture exactly how the ball-game crow is wired so we can faithfully reproduce the “feel” in the mining game (ECS), while avoiding prior brittleness.

## Asset Registration & Tagging

- Auto-setup: `ball game roblox/server/AI/RavenAutoSetup.server.lua`
  - Tags models as `AIRaven` (CollectionService) and adds attributes if missing.
  - Attributes set (animation IDs pulled from `ReplicatedStorage/AI/RavenAnimIds.lua`):
    - `FlyAnimId`, `FlyUpAnimId`, `FlyDownAnimId`, `IdleAnimId`, `CoreAnimId`, `AttackAnimId`, `WalkAnimId`, `RunAnimId`, `EatAnimId`.
    - Flight defaults: `FlightHeight` (25), `PatrolRadius` (35), `FlightSpeed` (4).
  - Notes: model can override; script runs on existing and future descendants; watches name changes.

- Binder: `server/AI/RavenBinder.server.lua`
  - On `AIRaven` add: removes `Animate` scripts and legacy body movers (BodyPosition/Gyro/etc.).
  - Creates `RavenAI` instance and optional debug HUD via `RavenDebug` (default Debug attribute true).
  - Ensures per-model preset hooks and idempotent attach/detach.

- Collision groups: `server/AI/PhysicsGroups.server.lua`
  - Registers groups `Crow`, `Hitbox`.
  - Sets Crow↔Crow and Crow↔Hitbox non-collide. Applies group to all BaseParts in crow models and watches for new parts.

## Animation System

- Track loading: `server/AI/RavenAI.lua` → `buildTracks()`
  - Loads animations from attributes into tracks with priorities:
    - Movement layer: `flight`, `flyUp`, `flyDown`, `walk`, `run`, `eat`, `attack`, and also `core` (continuous breathing) as Movement (used as base standing loop).
    - Ambient layer: `idle` with Idle priority (intermittent flourish overlay).

- Controller: `server/AI/Anim/AnimController.lua`
  - Intent-based API: states call `Anim:setIntent("flight"|"walk"|"run"|"breathing"|"eat")`.
  - Debounce: min 0.25s hold before base animation switch; prevents spam.
  - Flight variants: selects `flyUp`/`flyDown`/`flight` by vy with hysteresis (hold 0.18s).
  - Ambient: plays `idle` flourish every 8–14s for ~1.5s when base is `core` (breathing).
  - Speed scaling: uses `CrowTuning.Speed.AnimationSpeed` to adjust per intent.

- Key tuning: `shared/AI/CrowTuning.lua` → `Animation` and `Speed.AnimationSpeed` sections; `WalkToRunThreshold` for run flip; `FadeIn/FadeOut` for blend times.

## Physics & Movement

- Flight (AlignPosition/AlignOrientation): `server/AI/Locomotion/Flight.lua`
  - Creates one Attachment; AP and AO in OneAttachment mode; `ApplyAtCenterOfMass = true`.
  - Mass scaling: computes recommended `MaxForce` ≈ max(weight*2.5, configured) and torque scaled by mass; `retune()` called on enable.
  - Per-model overrides: attributes `AP_MaxForce`, `AP_MaxVelocity` if present.
  - `setEnabled(true)`: unanchors, sets network owner server, calls `retune()`.
  - `setTarget(pos, lookAt, upVec?)`: sets AP.Position; AO points toward `lookAt` with optional up vector (for landings/perches).

- Ground (Humanoid+Path): `server/AI/Locomotion/Ground.lua`
  - Uses PathfindingService with simple agent settings; MoveTo throttled.
  - Re-path cooldown: ≥0.6s and only if goal delta ≥4 studs; also periodic re-path at `Config.Tick.Path` cadence.
  - Waypoint handling: jumps when needed; increments waypoints when close; falls back to MoveTo(dest) if no waypoints.
  - On enable: sets `WalkSpeed = Tuning.Speed.WalkNormal`, JumpPower, clears when disabled.

- Stabilization & “unstick”: `server/AI/Physics/Stabilizer.lua`
  - Damps angular spin; adds lateral drag in flight to reduce side slip.
  - If position doesn’t change for ~1.2s, calls a re-aim callback (used by `RavenAI` to nudge target up).

## Steering & Sensing

- Obstacle avoidance: `server/AI/Steering/Avoidance.lua`
  - Simple forward/±25°/up rays; cadence ~0.15s; look-ahead by speed (clamped 12–60).
  - Excludes self model and all `Hitbox` tagged instances from ray hits; biases clear side and slight upward nudge.

- Separation (flock spacing): `server/AI/Steering/Separation.lua`
  - Nudge away from nearest raven within ~8–12 studs.

- World senses: `server/AI/Senses.lua`
  - Nearest player/food/perch/raven; perches use tag `RavenPerch`; food `CrowFood`.

## State & Behavior Highlights

- State manager: `server/AI/StateManager.lua`
  - Priority order: Flee > Eat > Follow > Social > Perch > Patrol; dwell time lock (`Tuning.Senses.StateDwell` ~5s).
  - Flee: trigger/resume radii from `Tuning.Flee`; min Flee duration; post-flee cooldown to prevent instant Follow.
  - Follow: uses `Tuning.Player.DetectionRadius`, `LoseInterestRadius`, `MaintainFollowRadius`, reacquire buffer/grace; exits to Perch on prolonged low activity.
  - Patrol: rotates between ground walk and fly on timers when no player near.

- Follow behavior: `server/AI/Behaviors/Follow.lua`
  - Ground/Air sub-modes selected with hysteresis and cooldowns; stores `_followMode` and `_lastModeSwitch`.
  - Comfort bubble: clamps to `Tuning.Player.FollowMinRadius` (default 18) on XZ; ground retreat when inside `minR - margin`.
  - Ground: ring targets around player at safe radius; lead/jitter; target refresh ~0.5s; MoveTo throttled; lateral sidestep when player approaches.
  - Air: behind/side/height anchor; orbit when player idle; horizontal spring smoothing; vertical altitude follow with AGL and climb/descend rate clamps.
  - Landing from air: if clamped at bubble edge for `LandClampHold` (0.05–0.35s) and player not sprinting, switch to ground (respects switch cooldown).
  - Lose-interest: clears follow target when beyond `LoseInterestRadius`.

## Debug & Logging

- HUD/labels: `server/AI/RavenDebug.lua` draws billboard with state and simple intent; refresh rate from `Tuning.Debug.HUDUpdateRate`.
- Logger: `server/AI/RavenLogger.lua` (ring buffer, log levels, dedupe window) consumed across modules.

## Important Tunables To Mirror

- Comfort & follow: `FollowMinRadius`, `GroundSwitchDistance`, `GroundSwitchHysteresis`, `FollowSwitchCooldown`, `FollowBehindDistance`, `FollowHeightOffset`, `IdleExitTime`.
- Follow (ground): `WalkChaseMin/MaxDistance`, `WalkChaseLead`, `WalkChaseRefresh`, `GroundJitter`.
- Flight: `CruiseAGL`, `MinAGL`, `ClimbRate`, `DescentRate`, `TakeoffImpulse`.
- Physics: `Physics.Position.{Responsiveness,MaxForce,MaxVelocity}`, `Physics.Orientation.{Responsiveness,MaxTorque,MaxAngularVelocity}`, `UseMassScaling`.
- Animation: `FadeIn/FadeOut`, `WalkToRunThreshold`, and `Speed.AnimationSpeed` per intent.

## Subtle Behaviors Worth Keeping

- Debounced animation intents with vy-based flight variant hysteresis.
- MoveTo throttling (goal delta + cooldown) to prevent path spam.
- Lateral sidestep when a player moves toward the crow (avoid head-on retreat).
- Flight velocity ramping (via AP.MaxVelocity changes + optional TakeoffImpulse kept small) to avoid “zoom away”.
- Flight lateral drag + “unstick” hop if stationary too long.
- Collision groups to avoid hitbox collisions and crow-on-crow bumps.

## Known Pain Points (Root Causes in Code)

- Ground↔Flight ping-pong: Depends on `GroundSwitchDistance` vs `FollowMinRadius` and insufficient dwell gates; fixed in Follow.lua by adding cooldowns and clamp-hold.
- Jerky ground movement: High `WalkNormal` (26) with frequent MoveTo reissues. The code added target refresh throttles and goal clamping—keep those.
- “Zoom away” in air: Large instantaneous target deltas + high AP.MaxVelocity; addressed by spring smoothing and vertical rate limits.

## Migration Guidance For Mining Game (ECS)

- Asset pipeline: replicate attributes & tags; a species-specific setup (or spawner) should apply the same attribute names so track loading works.
- Anim controller: keep intent debouncing, vy-variant hysteresis, ambient overlay; expose via ECS AnimationSystem.
- Flight: AlignPosition/Orientation with OneAttachment mode; mass-based MaxForce/torque; per-entity enable/disable with retune on enable.
- Ground: MoveTo + path with the same throttles (delta + cooldown) and waypoint handling; consider even slower Walk speed for caves.
- Steering/sensing: same ray scheme and cadence; share ignore lists via a world-query service.
- State: preserve Follow’s sticky ground/air logic, clamp-hold landing gate, retreat lateral bias, and lose-interest handling.
- Physics groups: create analogous collision groups and set model parts to avoid hitboxes/other animals.
- Debug: bring HUD and gizmos so we can verify dwell/hysteresis and targets in caves/trees/islands.

This audit captures the hard-won behaviors and wiring that made the ball-game crow feel good. The ECS plan should implement equivalent policies with data-driven configs and stricter cadence/dwell controls to preserve smoothness and reliability.

