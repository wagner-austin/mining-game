--!strict
-- ItemInsights.lua
-- Single source of item detail insights for UI popups (drop info, rarity, enhancements)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MG = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(MG:WaitForChild("GameConfig"))
local ItemDefinitions = require(MG:WaitForChild("ItemDefinitions"))

export type Insight = {
    id: string,
    name: string,
    type: string,
    slot: string?,
    rarity: string?,
    value: number?,
    icon: string?,
    enhanced: boolean?,
    perks: { [string]: any }?,
    baseDropChance: number?,
    rarityWeight: number?,
    rarityColor: Color3?,
    materialMultipliers: { { id: string, name: string, lootMultiplier: number } }?,
    sources: { string },
}

local ItemInsights = {}

local function rarityData(r: string?): (number?, Color3?)
    if not r then return nil, nil end
    local rar = GameConfig and GameConfig.Loot and GameConfig.Loot.RARITIES and GameConfig.Loot.RARITIES[r]
    if not rar then return nil, nil end
    return rar.weight, rar.color
end

local function listMaterials(): { { id: string, name: string, lootMultiplier: number } }
    local list = {}
    local mats = (GameConfig and GameConfig.CubeMaterials) or {}
    for _, m in ipairs(mats) do
        table.insert(list, { id = m.id, name = m.name, lootMultiplier = m.lootMultiplier or 1.0 })
    end
    table.sort(list, function(a, b) return (a.lootMultiplier or 1) > (b.lootMultiplier or 1) end)
    return list
end

local function determineSources(item: any): { string }
    local out = {}
    if not item then return out end
    if item.type == "resource" then
        table.insert(out, "Drops while digging")
    elseif item.type == "cosmetic" then
        -- Cosmetics can drop (if feature enabled) and/or be purchased
        if GameConfig.Features and GameConfig.Features.COSMETICS_IN_LOOT then
            table.insert(out, "Rare drop while digging")
        end
        table.insert(out, "Purchasable in Shop (coins)")
    elseif item.type == "consumable" then
        table.insert(out, "Usable item: grants temporary boosts")
    elseif item.type == "pickaxe" then
        table.insert(out, "Equip to change tool stats/appearance")
    end
    return out
end

function ItemInsights.get(itemId: string): Insight?
    local it = ItemDefinitions.get(itemId)
    if not it then return nil end
    local w, c = rarityData(it.rarity)
    local icon = (it :: any).icon or (it.meta and it.meta.icon)
    local enhanced = (it :: any).enhanced == true or (it.meta and it.meta.enhanced == true)
    local perks = (it :: any).perks or (it.meta and it.meta.perks)
    local mats = listMaterials()
    local base = GameConfig and GameConfig.Loot and GameConfig.Loot.BASE_DROP_CHANCE or nil
    return {
        id = it.id,
        name = it.name or it.id,
        type = it.type,
        slot = it.slot,
        rarity = it.rarity,
        value = it.value,
        icon = icon,
        enhanced = enhanced or nil,
        perks = perks or nil,
        baseDropChance = base,
        rarityWeight = w,
        rarityColor = c,
        materialMultipliers = mats,
        sources = determineSources(it),
    }
end

return ItemInsights

