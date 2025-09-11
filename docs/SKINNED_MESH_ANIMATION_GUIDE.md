# Skinned Mesh Animation Guide for Roblox

## Critical Discovery: Bone Transform Replication
**Issue:** Setting bone.Transform on the server does NOT visually replicate to clients.
**Reality:** 
- Transform values replicate (readable via code on client)
- Visual mesh deformation does NOT replicate
- This is an undocumented Roblox engine limitation

**Solution:** Manual replication via RemoteEvents - server calculates, clients apply transforms locally.

## Key Concepts

### 1. Client vs Server Animation
- **Server-owned meshes with client animation**: Recommended approach
  - Server owns the mesh (spawns it, positions it)
  - Client applies bone transforms for visual deformation
  - Use RemoteEvents to sync transform data
- **Pure client-side**: Works but mesh only exists for that client
- **Pure server-side**: Transforms won't visually replicate to clients!

### 2. Skinned Mesh Structure
```
Model or MeshPart
├── Bone (root)
├── Bone.001
├── Bone.002
└── InitialPoses (optional)
```

## Proper Server-Client Architecture

### Server Side (Calculation)
```lua
-- Server calculates bone transforms
local bones = mesh:GetDescendants()
local offsets = {}

RunService.Heartbeat:Connect(function()
    for i, bone in ipairs(bones) do
        if bone:IsA("Bone") then
            -- Calculate transform (physics, wave motion, etc)
            local transform = CFrame.new(x, y, z)
            offsets[i] = {transform.X, transform.Y, transform.Z}
        end
    end
    -- Send to all clients
    RemoteEvent:FireAllClients(meshId, offsets)
end)
```

### Client Side (Visual Application)
```lua
-- Client receives and applies transforms
RemoteEvent.OnClientEvent:Connect(function(meshId, offsets)
    local mesh = findMeshById(meshId)
    local bones = mesh:GetDescendants()
    
    for i, offset in ipairs(offsets) do
        if bones[i] and bones[i]:IsA("Bone") then
            bones[i].Transform = CFrame.new(offset[1], offset[2], offset[3])
        end
    end
end)
```

## How to Animate Skinned Meshes

### Step 1: Import Correctly
```lua
-- In Blender:
-- 1. Select mesh + armature
-- 2. Ctrl+P → With Automatic Weights
-- 3. Export as FBX with Armature included
-- 4. Import to Roblox (bones will be children of MeshPart)
```

### Step 2: Find Your Bones
```lua
-- Can be done on server or client
local mesh = workspace:WaitForChild("YourMesh")
local bones = {}

for _, child in ipairs(mesh:GetDescendants()) do
    if child:IsA("Bone") then
        table.insert(bones, child)
    end
end
```

### Step 3: Animate the Bones
```lua
-- Move bones using Transform property
RunService.RenderStepped:Connect(function()
    for i, bone in ipairs(bones) do
        -- Translation
        bone.Transform = CFrame.new(x, y, z)
        
        -- Rotation
        bone.Transform = CFrame.Angles(rx, ry, rz)
        
        -- Combined
        bone.Transform = CFrame.new(x, y, z) * CFrame.Angles(rx, ry, rz)
    end
end)
```

## Common Pitfalls & Solutions

### Mesh Not Deforming
**Problem:** Bones move but mesh stays rigid
**Solutions:**
1. If animating on server, you MUST send transforms to clients via RemoteEvents
2. Check vertex weights in Blender (Weight Paint mode)
3. Verify bones are direct children of MeshPart
4. Ensure client is applying transforms locally for visual update

### Server Transforms Don't Show on Client
**Problem:** Server sets bone.Transform but clients don't see deformation
**Solution:** This is expected behavior! Use RemoteEvents to send transform data to clients

### No Bones Found
**Problem:** Imported mesh has no Bone objects
**Solutions:**
1. Re-export from Blender with armature
2. Check "Import as Custom" in Roblox importer
3. Ensure FBX export settings include armature

### Bone Order Mismatch (Server vs Client)
**Problem:** Server and client apply transforms to different bones
**Solution:** Use bone indexing via Attributes
```lua
-- Server: Assign indices when spawning
for i, bone in ipairs(bones) do
    bone:SetAttribute("BoneIdx", i)
end

-- Client: Read indices to match order
local orderedBones = {}
for _, bone in ipairs(mesh:GetDescendants()) do
    if bone:IsA("Bone") then
        local idx = bone:GetAttribute("BoneIdx")
        if idx then orderedBones[idx] = bone end
    end
end
```

## Cloth Simulation Basics

### Physics Properties
```lua
local clothParams = {
    gravity = -0.15,      -- Downward force
    damping = 0.92,       -- Air resistance (0-1)
    stiffness = 0.3,      -- Spring between bones
    groundBounce = 0.2,   -- Energy kept when bouncing
}
```

### Verlet Integration (Stable Physics)
```lua
-- Store previous position instead of velocity
local oldPos = bone.Transform.Position
local currentPos = bone.Transform.Position

-- Calculate implicit velocity
local velocity = (currentPos - oldPos) * damping

-- Apply forces
velocity = velocity + Vector3.new(0, gravity, 0)

-- Update position
local newPos = currentPos + velocity
bone.Transform = CFrame.new(newPos)

-- Store for next frame
oldPos = currentPos
```

### Ground Collision
```lua
-- Raycast down to find ground
local ray = workspace:Raycast(
    bonePos + Vector3.new(0, 10, 0),
    Vector3.new(0, -20, 0)
)

if ray then
    local groundY = ray.Position.Y + 0.1  -- Small offset
    if bonePos.Y < groundY then
        -- Push back up
        bonePos = Vector3.new(bonePos.X, groundY, bonePos.Z)
    end
end
```

## Testing Checklist
- [ ] Mesh imported with bones visible in Explorer
- [ ] Server spawns mesh and assigns bone indices
- [ ] RemoteEvent created for transform updates
- [ ] Server calculates and sends transform data
- [ ] Client receives data and applies transforms
- [ ] Visual deformation occurs (watch mesh)
- [ ] Bone order matches between server and client

## Quick Debug Script
```lua
-- LocalScript: Test if bones can be animated locally
local mesh = workspace:WaitForChild("YourMeshName")
local bones = {}

for _, d in ipairs(mesh:GetDescendants()) do
    if d:IsA("Bone") then
        table.insert(bones, d)
    end
end

print("Found", #bones, "bones")

-- Simple wave test (this ONLY works if mesh is client-owned or via RemoteEvents)
game:GetService("RunService").RenderStepped:Connect(function()
    for i, bone in ipairs(bones) do
        bone.Transform = CFrame.new(0, math.sin(Time.mono() + i) * 2, 0)
    end
end)

-- WARNING: If mesh is server-owned and you're not using RemoteEvents,
-- you'll see bones move in properties but NO visual deformation!
```