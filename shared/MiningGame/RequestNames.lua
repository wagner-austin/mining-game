--!strict
local R = {
    INVENTORY_REQUEST_SELL   = "inventory.request.sell",
    INVENTORY_REQUEST_EQUIP  = "inventory.request.equip",
    DIG_REQUEST              = "dig.request",
    UPGRADE_REQUEST_PURCHASE = "upgrade.request.purchase",
    COSMETIC_REQUEST_EQUIP   = "cosmetic.request.equip",
    SETTINGS_UPDATE          = "settings.update",
    METRICS_REQUEST          = "metrics.request",
}

-- Build validation table for whitelists/tests
local VALID: {[string]: true} = {}
for _, v in pairs(R) do 
    if type(v) == "string" then 
        VALID[v] = true 
    end
end

-- Helper function to validate request names
function R.isValid(name: string): boolean
    return VALID[name] == true
end

table.freeze(R)

export type RequestName =
    "inventory.request.sell" | "inventory.request.equip" | "dig.request" |
    "upgrade.request.purchase" | "cosmetic.request.equip" | 
    "settings.update" | "metrics.request"

return R