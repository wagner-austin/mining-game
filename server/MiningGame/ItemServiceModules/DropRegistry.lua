--!strict
-- DropRegistry.lua
-- Centralizes active drop state, bookkeeping, and common helpers

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropRegistry = {}

type DropData = {
    owner: Player?,
    itemId: string,
    count: number,
    rarity: string?,
    value: number?,
    spawnTime: number,
    claimed: boolean,
}

export type StateT = {
    activeDrops: {[Model]: DropData},
    playerDropCounts: {[Player]: number},
    playerPickupCooldowns: {[Player]: number},
    hoverTweens: {[Model]: Tween},
    _bucket: {[string]: {[Model]: boolean}},
    _modelKey: {[Model]: string},
}

export type RegistryT = {
    state: StateT,
    registerDrop: (self: RegistryT, model: Model, data: DropData) -> (),
    removeDrop: (self: RegistryT, model: Model) -> (),
    getNearbyDrops: (self: RegistryT, position: Vector3, range: number) -> {Model},
    updateDropCountLabel: (self: RegistryT, model: Model, newCount: number) -> (),
}

function DropRegistry.new(ctx): RegistryT
    local ErrorService = ctx.ErrorService
    local MathUtils = ctx.MathUtils
    local LootService = ctx.LootService

    local state: StateT = {
        activeDrops = {},
        playerDropCounts = {},
        playerPickupCooldowns = {},
        hoverTweens = setmetatable({}, { __mode = "k" }),
        _bucket = {},
        _modelKey = setmetatable({}, { __mode = "k" }),
    }

    local BUCKET_SIZE = 64 -- studs; larger than max pickup range to bound buckets searched

    local function keyForPosition(pos: Vector3): string
        local gx = math.floor(pos.X / BUCKET_SIZE)
        local gz = math.floor(pos.Z / BUCKET_SIZE)
        return tostring(gx) .. ":" .. tostring(gz)
    end

    local function addToBucket(model: Model)
        if not (model and model.PrimaryPart) then return end
        local key = keyForPosition(model.PrimaryPart.Position)
        local b = state._bucket[key]
        if not b then b = {}; state._bucket[key] = b end
        b[model] = true
        state._modelKey[model] = key
    end

    local function removeFromBucket(model: Model)
        local key = state._modelKey[model]
        if key then
            local b = state._bucket[key]
            if b then b[model] = nil end
            state._modelKey[model] = nil
        end
    end

    local function registerDrop(model: Model, data: DropData)
        state.activeDrops[model] = data
        if data.owner then
            state.playerDropCounts[data.owner] = (state.playerDropCounts[data.owner] or 0) + 1
        end
        -- index into spatial bucket for faster queries
        addToBucket(model)
    end

    local function removeDrop(model: Model)
        local dropData = state.activeDrops[model]
        if dropData and dropData.owner then
            state.playerDropCounts[dropData.owner] = MathUtils.saturatingSub((state.playerDropCounts[dropData.owner] or 0), 1)
        end

        local hoverTween = state.hoverTweens[model]
        if hoverTween then
            ErrorService.safecall("Tween:Cancel", function() hoverTween:Cancel() end)
        end
        state.hoverTweens[model] = nil

        state.activeDrops[model] = nil
        removeFromBucket(model)
        if model then model:Destroy() end
    end

    local function getNearbyDrops(position: Vector3, range: number): {Model}
        local nearbyDrops = {}
        local gx0 = math.floor((position.X - range) / BUCKET_SIZE)
        local gx1 = math.floor((position.X + range) / BUCKET_SIZE)
        local gz0 = math.floor((position.Z - range) / BUCKET_SIZE)
        local gz1 = math.floor((position.Z + range) / BUCKET_SIZE)
        for gx = gx0, gx1 do
            for gz = gz0, gz1 do
                local key = tostring(gx) .. ":" .. tostring(gz)
                local bucket = state._bucket[key]
                if bucket then
                    for dropModel, _ in pairs(bucket) do
                        local data = state.activeDrops[dropModel]
                        if data and not data.claimed and dropModel.PrimaryPart then
                            local distance = (dropModel.PrimaryPart.Position - position).Magnitude
                            if distance <= range then
                                table.insert(nearbyDrops, dropModel)
                            end
                        end
                    end
                end
            end
        end
        return nearbyDrops
    end

    local function updateDropCountLabel(model: Model, newCount: number)
        if not model or not model.PrimaryPart then return end
        model:SetAttribute("Count", newCount)

        local part = model.PrimaryPart
        local bb = part:FindFirstChildOfClass("BillboardGui")
        if not bb then return end

        local nameLabel = bb:FindFirstChild("NameLabel") :: TextLabel?
        if not nameLabel then return end

        local itemId = model:GetAttribute("ItemId")
        if not itemId then return end

        local def = LootService:GetItemDefinition(itemId)
        if not def then return end

        local Shared = ReplicatedStorage:WaitForChild("MiningGame")
        local TextUtils = require(Shared:WaitForChild("TextUtils"))
        local displayName = TextUtils.prettifyItemName(itemId, def)
        nameLabel.Text = newCount > 1 and string.format("%s x%d", displayName, newCount) or displayName
    end

    return {
        state = state,
        registerDrop = registerDrop,
        removeDrop = removeDrop,
        getNearbyDrops = getNearbyDrops,
        updateDropCountLabel = updateDropCountLabel,
    }
end

return DropRegistry
