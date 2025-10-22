# RemoteFunction Specifications

This directory contains all RemoteFunction (RF) specifications for the MiningGame server.

## Architecture Overview

- **Single RF Gateway**: All RemoteFunctions are registered through `RFRegistry.lua`
- **Automatic Creation**: RemoteManager creates RF instances on-demand in `ReplicatedStorage.MiningGame.Remotes`
- **Strong Validation**: Every RF with parameters must have a `validate` function
- **Consistent Results**: User-facing RFs return top-level `{ ok, success, ... }`. ClientRF logs a warning in Studio if nested `data` is returned.
- **Schema Bridge**: RFRegistry converts each spec's `validate` into `opts.schema` required by RemoteManager

## Adding a New RF Spec

Create a new `.rf.lua` file or add to an existing one:

```lua
{
    name = "YourRFName",
    handler = function(ctx, param1, param2)
        -- ctx.player is always available
        -- ctx.profile is available if requireProfile = true
        
        -- Call your service
        local result = YourService:DoSomething(ctx.player, param1)
        
        -- Return top-level shape for user-facing RFs
        if result.success then
            return { ok = true, success = true, data = result.data }
        else
            return { ok = false, success = false, err = "ERROR_CODE", reason = "Error message" }
        end
    end,
    validate = function(param1, param2)
        -- Return true if parameters are valid
        if typeof(param1) ~= "string" then return false end
        if type(param2) ~= "number" then return false end
        return true
    end,
    opts = {
        requireProfile = true,    -- Default: true
        rateLimitSec = 0.5,      -- Required: seconds between calls
        debugOnly = false,       -- Optional: Studio-only RF
    }
}
```

## Conventions

### Naming
- Use PascalCase for RF names: `GetProfile`, `RequestDig`, `SellItems`
- Group related RFs in the same spec file

### Validation
- **Required** for any RF that accepts parameters
- Use `typeof()` for Roblox types (Vector3, CFrame, Instance)
- Use `type()` for Lua types (string, number, table)
- Return `false` to reject the request (triggers INVALID_REQUEST error)

### Rate Limiting
- **Required** on all RFs via `rateLimitSec`
- Use lower values (0.05-0.1) for high-frequency operations
- Use higher values (0.5-2.0) for expensive operations

### Debug-Only RFs
- Set `debugOnly = true` in opts
- Add `isDev()` check in handler for extra safety
- These RFs are only registered in Studio

## Client Usage

Clients use the standard Remotes module:

```lua
local Remotes = require(game.ReplicatedStorage.MiningGame.Remotes)

-- Direct usage
local result = Remotes.RF.GetProfile:InvokeServer()
if result.ok then
    print("Profile:", result.data)
else
    warn("Error:", result.err)
end

-- Using ClientRF helper
local RF = require(game.ReplicatedStorage.MiningGame.ClientRF)
local data, err = RF.call("GetProfile")
if not data then
    warn("Failed:", err)
end
```

## Current RF Specs

- `Cloth.rf.lua` - Cloth simulation debug tools (Studio-only)
- `Composition.rf.lua` - Material composition and regeneration
- `Core.rf.lua` - Core game functions and debug tools
- `CubeMaterial.rf.lua` - Cube material preferences
- `Dig.rf.lua` - Mining/digging operations
- `FloatingIsland.rf.lua` - Floating island generation (Studio-only)
- `Inventory.rf.lua` - Inventory management
- `Item.rf.lua` - Item pickup and spawning
- `Monetization.rf.lua` - Purchases and gamepasses
- `Neighborhood.rf.lua` - Multiplayer neighborhood features
- `Pets.rf.lua` - Pet system operations
- `Settings.rf.lua` - Player settings
- `SimAgents.rf.lua` - Simulation agents (Studio-only)
- `ThemeSettings.rf.lua` - Theme customization
- `Upgrade.rf.lua` - Player upgrade purchases

## Testing

In Studio console:
```lua
-- List all registered RFs
local RemotesFolder = game.ReplicatedStorage.MiningGame.Remotes
for _, inst in ipairs(RemotesFolder:GetChildren()) do
    if inst:IsA("RemoteFunction") then
        print(inst.Name)
    end
end

-- Test a specific RF
local Remotes = require(game.ReplicatedStorage.MiningGame.Remotes)
local result = Remotes.RF.YourRFName:InvokeServer(params)
print(result)
```

## Important Notes

- Never use `Remotes.RF` directly on the server - only RFRegistry should register RFs
- The schema bridge in RFRegistry converts `validate` to RemoteManager's required `schema`
- RemoteManager creates RF instances on-demand when first registered
- Clients auto-discover new RFs via the Remotes module's ChildAdded listener
