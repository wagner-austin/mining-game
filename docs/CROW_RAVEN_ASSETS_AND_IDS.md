# Crow/Raven Assets and IDs (for Mining Game Integration)

This document consolidates the asset identifiers (animations, model/mesh, sound) from the ball game repo, so we can quickly wire up a crow/raven in the mining game.

NOTE: These are the IDs present in the files today. If you re-upload or publish a model, Roblox will generate new asset IDs. Treat the “SourceAssetId” entries in .rbxmx as historical origins; prefer publishing your own assets and recording the final IDs you control.

## Animation IDs (from ball-game `shared/AI/RavenAnimIds.lua`)

- flyUp: `rbxassetid://91861165976987`
- idle (flourish overlay): `rbxassetid://112977643928147`
- flight (level): `rbxassetid://100858968045402`
- flightAtk: `rbxassetid://77786709928517`
- flyDown: `rbxassetid://88828624572153`
- eatDrink: `rbxassetid://117836889529307`
- running: `rbxassetid://134297202605580`
- birdAtk: `rbxassetid://130356717501858`
- core (breathing/standing base): `rbxassetid://113772079293723`
- walking: `rbxassetid://105519370766214`
- eating: `rbxassetid://93915215000045`

Attribute mapping expected on the model (Autoconfig or manual):
- `FlyAnimId` ← flight
- `FlyUpAnimId` ← flyUp
- `FlyDownAnimId` ← flyDown
- `IdleAnimId` ← idle (overlay)
- `CoreAnimId` ← core (breathing)
- `AttackAnimId` ← birdAtk (or flightAtk for airborne variations)
- `WalkAnimId` ← walking
- `RunAnimId` ← running
- `EatAnimId` ← eating or eatDrink
- `CawSoundId` ← crow caw sound (see below)

## Crow (simple mesh with sound) — IDs from `assets/crow - with sound.rbxmx`

- SoundId (caw): `rbxassetid://64488575`
- MeshId: `rbxassetid://105334700`
- TextureId: `rbxassetid://105334729`
- Part SourceAssetId (origin): `133786932` (historical reference)

Use case:
- You can reuse the caw sound on the animated raven by setting model attribute `CawSoundId = "rbxassetid://64488575"`.
- The mesh model is not rigged/animated; it’s mainly a legacy prop with caw.

## Raven (rigged, used by AI) — file: `assets/night raven rigged with animations.rbxmx`

- This file contains a rigged model suited for Animator-driven clips. It does not itself store the animation assets; those are referenced via attributes at runtime.
- Candidate SourceAssetIds seen in the file (for provenance):
  - Top-level model/parts include entries like `SourceAssetId = 633430850` (and various others for subparts). Treat these as original upload references.
- Recommendation: Publish your preferred rig as a Roblox Model under your account and record that Model’s AssetId here for InsertService usage, or place the model in `ReplicatedStorage` for direct cloning.

## Quick Spawn Approaches (no code snippets, just options)

- ReplicatedStorage clone (recommended for stability):
  - Place the raven rig under `ReplicatedStorage/MiningGame/AI/Models/CrowRaven`.
  - At runtime, clone the model, parent to workspace, set attributes listed above (animation IDs + optional `CawSoundId`).
  - Tag the model with your creature tag (e.g., `AIRaven` or `AICreature`) so the binder/AI attaches.

- InsertService by AssetId (only if published):
  - Publish the rig as a Model to Roblox and note the Model’s AssetId here.
  - Load via server InsertService and apply the same attributes/tag.

## Minimal Attribute Checklist (per spawned raven model)

- Animation attributes:
  - `FlyAnimId`, `FlyUpAnimId`, `FlyDownAnimId`, `IdleAnimId`, `CoreAnimId`, `AttackAnimId`, `WalkAnimId`, `RunAnimId`, `EatAnimId`
- Optional sound:
  - `CawSoundId = rbxassetid://64488575`
- Optional flight tuning overrides (if needed):
  - `AP_MaxForce`, `AP_MaxVelocity`
- Behavior tuning (if your system supports per-instance):
  - `FlightHeight`, `PatrolRadius`, `FlightSpeed`, `Debug`

## Recommended Next Step

- Decide whether to reuse the existing rig from the repo or publish a cleaned/prefabbed version as a Model under your account.
- If publishing, update this page with the final Model AssetId and confirm permissions.
- Keep animation IDs in sync with `RavenAnimIds.lua` (or your mining-game equivalent) so autoconfig/binder can populate attributes reliably.

