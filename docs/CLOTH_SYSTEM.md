# Cloth Simulation System Documentation

## Overview
The cloth simulation system provides server-authoritative bone-based mesh deformation for cloth-like objects in Roblox. The system uses a curtain-hanging model with wave motion to simulate cloth behavior.

## Critical Discovery: Bone Transform Replication Issue

### The Problem
**Bone transforms set on the server DO NOT replicate visually to clients in Roblox.** This is a fundamental limitation of the Roblox engine that is not well-documented.

When you set `bone.Transform` on the server:
- The transform value DOES replicate to clients (readable via code)
- The visual mesh deformation DOES NOT update on clients
- This creates a disconnect between the data and visual state

### The Solution
We implement a manual replication system using the EventBus (bridged to clients via RemoteEvent):
1. Server calculates bone transforms each frame
2. Server sends transform data via RemoteEvent to each client
3. Clients apply the transforms locally for visual updates

## Architecture

### Files Structure
```
server/
  Cloth/
    init.server.lua           # Legacy bootstrap (unused)
  CreateClothTool.server.lua.disabled  # Studio-only test tool (disabled)

client/
  BannerAnimator.client.lua         # Client-side cloth animation (no server updates)
  ClothToolClient.client.lua.disabled  # Studio-only test tool client (disabled)

shared/
  MiningGame/
    Cloth/
      ClothBase.lua           # Reusable cloth base (spawn/compute/helpers)
    Remotes.lua               # Remote definitions
```

Cloth animation for banners and scenic use is client-driven; no server cloth simulation service is registered.

### Remote Communication
No dedicated cloth RemoteFunctions are provided. Spawn cloth in services (e.g., BannerService) and animate on the client. The server does not emit cloth updates.

## Implementation Details

### Bone Grid Structure
The cloth mesh uses a column-row grid of bones:
- **5 columns** of bones (sorted by X position)
- **~12 rows** per column (parent-child chains)
- Root bones (row 1) attach to the mesh and act as the "curtain rod"
- Child bones follow in a hierarchical chain

```lua
-- Grid building process
1. Find all root bones (parent is MeshPart, not another Bone)
2. Sort roots by X position to establish columns
3. Walk down each root's child chain to build rows
4. Create metadata: {col: number, row: number, rowsInCol: number}
```

### Wave Simulation Parameters

```lua
local waveSpeed = 2.0      -- Speed of wave motion
local waveLength = 3.0     -- Distance between wave peaks  
local zAmplitude = 2.0     -- Forward/back movement amplitude
local stretchAmount = 0.15 -- Vertical stretch between bones
```

#### Transform Calculation
For each bone:
1. **Root bones (row 1)**: No transform, stays anchored
2. **Other bones**:
   - **Gravity droop**: `(row - 1) * stretchAmount`
   - **Wave strength**: `v * v` where v is normalized row position (stronger at bottom)
   - **Forward wave**: `sin(waveSpeed * t + u * waveLength * π) * zAmplitude * waveStrength`
   - **Side sway**: `sin(waveSpeed * t * 0.7 + u * π * 2) * 0.2 * waveStrength`

### Bone Indexing System
To ensure server and client agree on bone ordering:

1. **Server** assigns indices during spawn:
```lua
for i, bone in ipairs(bones) do
    bone:SetAttribute("ClothIdx", i)
end
```

2. **Client** reads indices to rebuild array:
```lua
local bones = {}
for _, desc in ipairs(mesh:GetDescendants()) do
    if desc:IsA("Bone") then
        local idx = desc:GetAttribute("ClothIdx")
        if typeof(idx) == "number" then
            bones[idx] = desc
        end
    end
end
```

### Transform Data Format
Offsets are sent as tables with 3 components:
```lua
-- Server sends:
offsets[i] = {xSway, gravityDroop, forwardWave * 0.5}

-- Client receives:
local x = offset[1] or 0
local y = offset[2] or 0  
local z = offset[3] or 0
bone.Transform = CFrame.new(x, y, z)
```

## Debug Visualization
Each bone has a colored sphere for debugging:
- Different colors per column (rainbow gradient)
- Larger spheres for root bones (0.5 vs 0.3 studs)
- Updates position each frame to match bone WorldCFrame
- Toggle visibility: `sphere.Transparency = 0` (visible) or `1` (hidden)

## Usage

### Tool-Based Spawning
In Studio, you can build your own quick test tool that clones the cloth template under your character and uses `ClothBase.buildGrid` to map bones. Server remotes for cloth spawning have been removed.

### Manual Spawning (Server-Side)
Use `ClothBase.spawnFromTemplate` directly in your service/script (see BannerService for example patterns).

### Cloth Properties
- **Position**: 20 studs above, 10 studs in front of player
- **Orientation**: Rotated -90° (hanging) + 180° Y rotation
- **Material**: Glass (dark blue tint)
- **Lighting**: Neon uplight pad (SurfaceLight) for upward glow
- **Physics**: Anchored, CanCollide enabled (player can stand on it)

## Performance Considerations

### Update Frequency
- Client animates at ~30 FPS using BannerAnimator (or similar). No server cloth updates are sent.

### Debug Logging
- Logs every 60 frames to reduce spam
- Tracks frame count and offset counts
- First bone position logged periodically

## Common Issues and Solutions

### Issue: Cloth appears rigid, no movement
**Cause**: Client animator not attached or skin disabled
**Solution**: Verify `Skin.Enabled = true` on the MeshPart, and that your client animator is mounting (e.g., via BANNER_READY).

### Issue: Bones moving incorrectly (inchworm effect)
**Cause**: Cumulative transforms in parent-child hierarchy
**Solution**: Only move root bones, let children follow naturally

### Issue: Index mismatch between server/client
**Cause**: Different bone ordering
**Solution**: Use ClothIdx attributes for consistent indexing

### Issue: Cloth orientation wrong
**Cause**: Bone space vs world space confusion
**Solution**: Remember Y is down, Z is forward/back in rotated bone space

## Wave Motion Mathematics

### Column Position (u)
```lua
u = (column - 1) / max(numColumns - 1, 1)  -- Normalized 0-1
```

### Row Position (v)  
```lua
v = (row - 1) / max(rowsInColumn - 1, 1)  -- Normalized 0-1
```

### Wave Function
```lua
wave = sin(speed * time + u * wavelength * π) * amplitude * (v * v)
```
The `v * v` term makes waves stronger at the bottom of the curtain.

## Asset Pipeline

### Why Roblox Asset IDs?
Skinned MeshParts lose their `Skin` data when exported to `.rbxm`/`.rbxmx`, so the mesh won't deform if we clone those files. Publishing the cloth to Roblox as a model (asset ID `116193032143091`) and cloning it at runtime keeps the `Skin` intact.

### Publishing Steps
1. Import the FBX into Studio and verify it deforms.
2. Save it to Roblox (Model or Package) so the skin lives in the published asset.
3. Store your cloth asset under ReplicatedStorage.MiningGame.Assets for easy cloning.

### Runtime Loading
Preferred: Package the asset under `ReplicatedStorage.MiningGame.Assets` (e.g., `BlanketPlane`) and clone it; ensure `Skin.Enabled = true`.

Also supported: If the asset is not packaged, the server attempts to load the published model by ID via `InsertService:LoadAsset` (Studio and live, subject to permissions). On success, it caches the result under `ReplicatedStorage.MiningGame.Assets.BlanketPlane` for reuse and client replication. On failure (e.g., private asset), it logs a clear error.

### Skin Safety Check
After cloning, we call `FindFirstChildOfClass("Skin")` and enable it. If the skin is missing we log a warning; the cloth will fall back to a rigid mesh.

### Rojo Considerations
Rojo won't sync skinned MeshParts directly. Keep a `PackageLink` or loader script under `shared/MiningGame/Assets` so Studio refreshes the asset from Roblox instead of a local `.rbxm`.
## Testing and Debugging

### Enable Debug Spheres
In your spawner (e.g., BannerService debug spheres section):
```lua
sphere.Transparency = 0  -- Show spheres
```

### Monitor Network Traffic
Check RemoteEvent firing in server logs:
```
Frame 60: Sending 60 offsets to Player1, first=0.00
```

### Verify Client Reception  
Client prints when receiving updates:
```
BannerAnimator: Animating N bones at ~30 FPS (client-only)
  Bone 1: x=0.00, y=0.00, z=0.00
```

## Future Enhancements
- Drag interaction (currently removed for simplicity)
- Wind effects
- Collision response
- Multiple cloth instances per player
- Tearable cloth with bone removal
- Performance LOD system


