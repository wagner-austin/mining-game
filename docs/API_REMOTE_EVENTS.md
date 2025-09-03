# RemoteEvents API Reference

[← Back to API Documentation](API_DOCUMENTATION.md)

## Overview

RemoteEvents are used for server→client notifications. These are fire-and-forget messages that don't expect a response. The server fires these events to notify clients of state changes, effects, and other updates.

## Table of Contents

- [State Updates](#state-updates)
- [Dig Feedback](#dig-feedback)
- [Social Events](#social-events)
- [Notifications](#notifications)
- [UI Prompts](#ui-prompts)
- [Effects](#effects)
- [Event Connection Best Practices](#event-connection-best-practices)

**Total Events: 26**

---

## State Updates

### `OnProfileUpdate`
Fired when player's complete profile data updates.

**Payload:**
```lua
{
    stats: PlayerStats,
    inventory: Inventory,
    upgrades: Upgrades,
    settings: Settings
}
```

**When Fired:**
- On initial player join
- After major state changes
- On profile recovery

---

### `OnCurrencyChanged`
Fired when player's currency changes.

**Payload:**
```lua
{
    coins = number?,
    gems = number?,
    delta = {
        coins = number?,    -- Change amount
        gems = number?      -- Change amount
    }
}
```

**Usage Example:**
```lua
Remotes.RE.OnCurrencyChanged.OnClientEvent:Connect(function(data)
    if data.coins then
        updateCoinDisplay(data.coins)
        if data.delta.coins > 0 then
            showCoinAnimation("+" .. data.delta.coins)
        end
    end
end)
```

### `OnInventoryChanged`
Fired when inventory is modified.

**Payload:**
```lua
{
    action = "add" | "remove" | "equip" | "unequip",
    itemId = string,
    count = number?,      -- For add/remove
    total = number?,      -- New total count
    slot = string?        -- For equip/unequip
}
```

**Usage Example:**
```lua
Remotes.RE.OnInventoryChanged.OnClientEvent:Connect(function(payload)
    if payload.action == "add" then
        showItemNotification(payload.itemId, payload.count)
    elseif payload.action == "equip" then
        updateEquipmentDisplay(payload.slot, payload.itemId)
    end
end)
```

### `OnUpgradesChanged`
Fired when upgrades are purchased.

**Payload:**
```lua
{
    upgrades = {
        speed = number,
        size = number
    },
    coins = number  -- New coin balance after purchase
}
```

### `OnBoostsChanged`
Fired when boost status changes.

**Payload:**
```lua
{
    [boostType: string] = expiryTime: number  -- Unix timestamp when boost expires
}
```

**Usage Example:**
```lua
Remotes.RE.OnBoostsChanged.OnClientEvent:Connect(function(boosts)
    for boostType, expiryTime in pairs(boosts) do
        local remaining = expiryTime - os.time()
        if remaining > 0 then
            showBoostTimer(boostType, remaining)
        else
            hideBoostTimer(boostType)
        end
    end
end)
```

### `OnPetsChanged`
Fired when pet status changes.

**Payload:**
```lua
{
    action = "equipped" | "unequipped" | "upgraded",
    petId = string,
    petData = PetData?  -- For equipped/upgraded
}
```

---

## Dig Feedback

### `OnDigFeedback`
Fired after successful dig for visual/audio feedback.

**Payload:**
```lua
{
    cells = {
        {x = number, y = number, z = number}  -- Cell coordinates destroyed
    },
    shake = boolean,      -- Apply camera shake
    particles = boolean,  -- Show particle effects
    sound = string?       -- Sound ID to play
}
```

**Usage Example:**
```lua
Remotes.RE.OnDigFeedback.OnClientEvent:Connect(function(feedback)
    if feedback.shake then
        cameraShake(0.1, 0.15)  -- intensity, duration
    end
    
    if feedback.particles then
        for _, cell in ipairs(feedback.cells) do
            spawnDigParticles(cell)
        end
    end
    
    if feedback.sound then
        playSound(feedback.sound)
    end
end)
```

### `OnTerrainUpdate`
Fired when terrain is modified (for visual updates).

**Payload:**
```lua
{
    region = Region3,
    material = Enum.Material
}
```

### `OnLootDropped`
Fired when loot spawns from digging.

**Payload:**
```lua
{
    item = {
        id = string,
        rarity = string,      -- "common", "rare", "epic", "legendary"
        count = number
    },
    worldPos = Vector3,       -- Where the loot spawned
    value = number?           -- Coin value if sold
}
```

**Usage Example:**
```lua
Remotes.RE.OnLootDropped.OnClientEvent:Connect(function(loot)
    -- Create floating UI at world position
    local rarityColor = getRarityColor(loot.item.rarity)
    createLootPopup(loot.worldPos, loot.item.id, loot.item.count, rarityColor)
    
    -- Play rarity-specific sound
    playLootSound(loot.item.rarity)
end)
```

### `OnFirstDig`
Fired when a player digs for the first time.

**Payload:**
```lua
{
    message = string,         -- Welcome/tutorial message
    reward = {
        coins = number?,
        gems = number?
    }
}
```

---

## Social Events

### `OnNeighborJoined`
Fired when a neighbor joins your cube area.

**Payload:**
```lua
{
    userId: number,
    username: string,
    displayName: string
}
```

**When Fired:**
- When another player visits your cube

---

### `OnNeighborLeft`
Fired when a neighbor leaves your cube area.

**Payload:**
```lua
{
    userId: number,
    username: string
}
```

**When Fired:**
- When visiting player leaves
- When visiting player disconnects

---

### `OnCubeUpdate`
Fired when cube state changes significantly.

**Payload:**
```lua
{
    cubeId: string,
    tier: string,
    extraction: number,
    percentComplete: number
}
```

**When Fired:**
- Cube tier changes
- Extraction milestones reached
- Cube reset/regeneration

---

## Notifications

### `OnNotification`
General notification system for various messages.

**Payload:**
```lua
{
    type = "info" | "success" | "warning" | "error",
    message = string,
    title = string?,          -- Optional title
    duration = number?,       -- Seconds to display (default: 3)
    color = Color3?,         -- Custom color override
    icon = string?           -- Icon asset ID
}
```

**Usage Example:**
```lua
Remotes.RE.OnNotification.OnClientEvent:Connect(function(notif)
    local color = notif.color or getNotificationColor(notif.type)
    local duration = notif.duration or 3
    
    showNotification({
        title = notif.title or getNotificationTitle(notif.type),
        message = notif.message,
        color = color,
        duration = duration,
        icon = notif.icon
    })
end)
```

### `OnReward`
Special notification for rewards and bonuses.

**Payload:**
```lua
{
    type = "coins" | "gems" | "item" | "boost",
    amount = number | string,  -- Number for currency, string for items
    source = string,           -- Where reward came from (e.g., "Daily Bonus", "Achievement")
    multiplier = number?       -- If reward was boosted
}
```

**Usage Example:**
```lua
Remotes.RE.OnReward.OnClientEvent:Connect(function(reward)
    if reward.type == "coins" or reward.type == "gems" then
        local displayAmount = reward.amount
        if reward.multiplier then
            displayAmount = displayAmount .. " (x" .. reward.multiplier .. ")"
        end
        showRewardPopup(reward.type, displayAmount, reward.source)
    elseif reward.type == "item" then
        showItemReward(reward.amount, reward.source)
    end
end)
```

### `OnAchievement`
Fired when player unlocks an achievement.

**Payload:**
```lua
{
    id = string,              -- Achievement ID
    name = string,            -- Display name
    description = string,     -- Achievement description
    reward = {
        coins = number?,
        gems = number?,
        items = {string}?
    }
}
```

### `OnItemCollected`
Fired when an item is successfully collected.

**Payload:**
```lua
{
    itemId = string,
    count = number,
    rarity = string,
    value = number?           -- Sell value
}
```

---

## UI Prompts

### `ShowPickupPrompt`
Display pickup prompt for nearby items.

**Payload:**
```lua
{
    dropModel = Model,        -- The drop model in workspace
    itemData = {
        id = string,
        name = string,
        rarity = string,
        value = number
    },
    distance = number         -- Distance from player
}
```

**Usage Example:**
```lua
Remotes.RE.ShowPickupPrompt.OnClientEvent:Connect(function(prompt)
    -- Show proximity prompt
    if prompt.distance < 10 then
        showPickupUI(prompt.itemData, function()
            -- Player pressed pickup button
            Remotes.RF.PickupItem:InvokeServer(prompt.dropModel)
        end)
    end
end)
```

---

## Effects

### `PlaySound`
Play a sound effect on the client.

**Payload:**
```lua
{
    soundId = string,         -- Sound asset ID
    volume = number?,         -- Volume (0-1, default: 0.5)
    pitch = number?,          -- Pitch (0.5-2, default: 1)
    position = Vector3?       -- 3D sound position (nil for 2D)
}
```

**Usage Example:**
```lua
Remotes.RE.PlaySound.OnClientEvent:Connect(function(data)
    local sound = Instance.new("Sound")
    sound.SoundId = data.soundId
    sound.Volume = data.volume or 0.5
    sound.Pitch = data.pitch or 1
    
    if data.position then
        -- 3D sound
        local part = Instance.new("Part")
        part.Position = data.position
        part.Anchored = true
        part.CanCollide = false
        part.Transparency = 1
        part.Parent = workspace
        sound.Parent = part
        
        sound.Ended:Connect(function()
            part:Destroy()
        end)
    else
        -- 2D sound
        sound.Parent = workspace.CurrentCamera
    end
    
    sound:Play()
end)
```

### `OnSoundEffect`
Alternative sound effect event with named sounds.

**Payload:**
```lua
{
    name = string,            -- Sound name from config
    properties = {
        Volume = number?,
        Pitch = number?,
        EmitterSize = number?
    }
}
```

### `OnParticleEffect`
Trigger particle effects at a position.

**Payload:**
```lua
{
    effectType = string,      -- Effect name
    position = Vector3,
    duration = number?,       -- How long to emit
    properties = {           -- Optional overrides
        Color = ColorSequence?,
        Size = NumberSequence?,
        Rate = number?
    }
}
```

### `OnCameraShake`
Trigger camera shake effect.

**Payload:**
```lua
{
    intensity = number,       -- Shake intensity (0.1-1.0)
    duration = number        -- Duration in seconds
}
```

**Usage Example:**
```lua
Remotes.RE.OnCameraShake.OnClientEvent:Connect(function(data)
    local camera = workspace.CurrentCamera
    local originalCFrame = camera.CFrame
    local shakeTime = 0
    
    RunService.RenderStepped:Connect(function(dt)
        shakeTime = shakeTime + dt
        if shakeTime < data.duration then
            local shake = math.random() * data.intensity
            camera.CFrame = originalCFrame * CFrame.Angles(
                math.rad(shake),
                math.rad(shake),
                0
            )
        else
            camera.CFrame = originalCFrame
            return -- Disconnect
        end
    end)
end)
```

### `OnCubeOriginChanged`
Fired when the player's cube origin is set or changed.

**Payload:**
```lua
CFrame  -- The cube's origin position and rotation
```

**Usage Example:**
```lua
Remotes.RE.OnCubeOriginChanged.OnClientEvent:Connect(function(origin)
    -- Store cube origin for client-side calculations
    playerCubeOrigin = origin
    
    -- Update any UI or systems that depend on cube position
    if visualFeedback then
        visualFeedback:SetCubeOrigin(origin)
    end
end)
```

### `OnTerrainPoke`
Debug event for terrain manipulation feedback.

**Payload:**
```lua
{
    position = Vector3,
    radius = number,
    success = boolean
}
```

---

### `ClothUpdate`
Fired to update cloth bone transforms on client.

**Payload:**
```lua
clothId: string,      -- Unique cloth instance ID
offsets: {            -- Array of bone transform offsets
    {x: number, y: number, z: number}
}
```

**When Fired:**
- Every frame (60Hz) while cloth is active
- Server calculates physics, client applies visuals

**Usage Example:**
```lua
Remotes.RE.ClothUpdate.OnClientEvent:Connect(function(clothId, offsets)
    local cloth = findClothById(clothId)
    if cloth then
        for i, offset in ipairs(offsets) do
            local bone = cloth.bones[i]
            if bone then
                bone.Transform = CFrame.new(offset[1], offset[2], offset[3])
            end
        end
    end
end)
```

---

## Event Connection Best Practices

### Memory Management
Always store connections and clean them up when no longer needed:

```lua
local connections = {}

-- Connect events
connections.currency = Remotes.RE.OnCurrencyChanged.OnClientEvent:Connect(onCurrencyChanged)
connections.inventory = Remotes.RE.OnInventoryChanged.OnClientEvent:Connect(onInventoryChanged)

-- Clean up when UI is destroyed
local function cleanup()
    for _, connection in pairs(connections) do
        connection:Disconnect()
    end
    connections = {}
end
```

### Error Handling
Wrap event handlers in pcall for safety:

```lua
Remotes.RE.OnNotification.OnClientEvent:Connect(function(data)
    local success, err = pcall(function()
        processNotification(data)
    end)
    
    if not success then
        warn("Notification handler error:", err)
    end
end)
```

### Validation
Always validate data from RemoteEvents:

```lua
Remotes.RE.OnCurrencyChanged.OnClientEvent:Connect(function(data)
    -- Validate data structure
    if type(data) ~= "table" then return end
    
    -- Validate number values
    if data.coins and type(data.coins) == "number" then
        updateCoins(math.max(0, data.coins))
    end
end)
```

[← RemoteFunctions](API_REMOTE_FUNCTIONS.md) | [Best Practices →](API_BEST_PRACTICES.md)