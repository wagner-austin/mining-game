# Cloth Base (Reusable)

This module provides a reusable base for cloth-like skinned meshes so you can:
- Place cloth as part of static or dynamic scenery (e.g., banners, flags).
- Reuse the same logic for future UIs (e.g., a high-score board cloth) by composing a Text/SurfaceGui on top.

Paths:
- `shared/MiningGame/Cloth/Base.lua`

## API

Require path (server or client):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local ClothBase = require(MiningGame:WaitForChild("Cloth"):WaitForChild("ClothBase"))
```

### spawnFromTemplate(template, opts) -> ClothInstance
Clones a skinned cloth template (Model or MeshPart), wraps in a `Model` if needed, applies visuals/physics, indexes bones, and returns a `ClothInstance`.

Key `opts`:
- `parent` (Instance, default `workspace`)
- `name` (string)
- `cframe` (CFrame) — placement/orientation; for a hanging cloth use `CFrame.Angles(math.rad(-90), math.rad(180), 0)`
- `anchored`, `canCollide`, `canQuery`, `canTouch` (booleans)
- `scale` (number) — uniform scale factor (uses `Model:ScaleTo` when possible)
- `widen` (number) — multiply MeshPart `Size.X`
- `idAttribute` (string, default `"ClothId"`); `id` (string, default GUID)
- `visual` (table): `material`, `color`, `transparency`, `reflectance`, `castShadow`, `clearSurfaceAppearance`, `clearHighlights`, `materialVariant`
- `makeDebugSpheres` (bool) — adds optional white orbs with lights (icicle effect)
- `glowBar` (table): `{ enabled, thickness, width, extraLen, shortenFactor }`

Returns a `ClothInstance` with fields: `id`, `model`, `mesh`, `bones`, `columns`, `meta`, `numCols`, `maxRows`, `debugParts?`.

### computeOffsets(inst, t, params) -> {Vector3}
Generates simple curtain-like offsets for each bone at time `t` using optional params:
`waveSpeed`, `waveLength`, `zAmplitude`, `stretchAmount`.

### updateDebug(inst, t)
If `makeDebugSpheres` was enabled, updates the white-orb effect.

## Example: Scenic Banner

```lua
-- Server-side example (Studio-only asset load)
-- Note: InsertService:LoadAsset works in Studio. In live games,
-- package the skinned asset under ReplicatedStorage.MiningGame.Assets (e.g., "BlanketPlane").
local InsertService = game:GetService("InsertService")
local template = InsertService:LoadAsset(116193032143091) -- published model with Skin
local cloth = ClothBase.spawnFromTemplate(template, {
    parent = workspace,
    name = "ScenicBanner",
    cframe = CFrame.new(0, 20, 0) * CFrame.Angles(math.rad(-90), math.rad(180), 0),
    visual = {
        material = Enum.Material.Glass,
        color = Color3.fromRGB(10, 30, 170),
        transparency = 0.6,
        reflectance = 0.08,
        castShadow = false,
        clearSurfaceAppearance = true,
        clearHighlights = true,
        materialVariant = "",
    },
    anchored = true,
    canCollide = true,
    scale = 0.6,
    widen = 1.05,
    glowBar = { enabled = true },
})

-- Optionally animate on server and replicate to clients via your own bus
-- local offsets = ClothBase.computeOffsets(cloth, time())
```

## High Score Board Notes

- Mount a `SurfaceGui` or `BillboardGui` to the cloth’s `mesh` or to an adjacent frame to render text.
- Keep the cloth’s motion subtle (`zAmplitude` small) to make text legible.
- You can also disable motion entirely by sending zero offsets from your controller.

## Integration Notes

The previous `SimpleClothService` has been retired. Use `ClothBase.spawnFromTemplate` directly (as in BannerService) and client-side animation (e.g., `BannerAnimator.client.lua`).
