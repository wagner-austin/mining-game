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
    }

    local function registerDrop(model: Model, data: DropData)
        state.activeDrops[model] = data
        if data.owner then
            state.playerDropCounts[data.owner] = (state.playerDropCounts[data.owner] or 0) + 1
        end
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
        if model then model:Destroy() end
    end

    local function getNearbyDrops(position: Vector3, range: number): {Model}
        local nearbyDrops = {}
        for dropModel, dropData in pairs(state.activeDrops) do
            if dropModel.PrimaryPart and not dropData.claimed then
                local distance = (dropModel.PrimaryPart.Position - position).Magnitude
                if distance <= range then
                    table.insert(nearbyDrops, dropModel)
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
