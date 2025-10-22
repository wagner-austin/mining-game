-- CashShopCoinsTab.lua - Passes tab (Roblox Gamepasses) styled like Cosmetics: tile + price button row

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))
local ItemTileRenderer = require(script.Parent:WaitForChild("ItemTileRenderer"))
local ShopGridHelpers = require(script.Parent:WaitForChild("ShopGridHelpers"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local Remotes = require(MiningGame:WaitForChild("Remotes"))
local UIUtils = require(UIFolder:WaitForChild("UIUtils"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("ShopPasses")

type Props = { parent: Instance }

local CashShopCoinsTab = {}
CashShopCoinsTab.__index = CashShopCoinsTab
setmetatable(CashShopCoinsTab, { __index = BaseTabComponent })

local function hasRF(name: string): boolean
    return Remotes.RF[name] ~= nil
end

function CashShopCoinsTab.new(props: Props)
    local self: any = setmetatable(BaseTabComponent.new({ parent = props.parent, stacked = true, name = "CashShopCoinsTab" }), CashShopCoinsTab)

    -- Scrollable card section consistent with other panels
    local _, gridScroll, grid = self:createScrollableSection("Passes", UIx.Size.INVENTORY_MIN_HEIGHT)
    -- Override grid layout to match shop cell sizing
    grid.CellSize = UDim2.new(0, UIx.Size.INVENTORY_CELL_WIDTH, 0, UIx.Size.INVENTORY_CELL_HEIGHT + UIx.Size.ROW_STANDARD + UIx.Spacing.SM + 2)
    grid.CellPadding = UDim2.new(0, UIx.Spacing.SM, 0, UIx.Spacing.SM)
    self._grid = gridScroll

    return self
end

function CashShopCoinsTab:refresh()
    local gridScroll: ScrollingFrame = self._grid
    if not gridScroll then return end
    for _, ch in ipairs(gridScroll:GetChildren()) do if ch:IsA("GuiObject") then ch:Destroy() end end

    if not hasRF("GetGamepasses") then
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -UIx.Spacing.SM, 0, UIx.Size.ROW_SECTION)
        lbl.Position = UDim2.new(0, UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
        lbl.BackgroundTransparency = 1
        lbl.Text = "Passes shop unavailable"
        lbl.TextScaled = true
        lbl.Font = Theme.fonts.Secondary
        lbl.TextColor3 = Theme.colors.Text
        lbl.Parent = gridScroll
        return
    end

    local passes = {}
    do
        local ok, res = pcall(function()
            return ClientRF.call("GetGamepasses")
        end)
        if ok and res and res.list then
            passes = res.list
        end
    end

    -- Server already filters to configured passes only

    if #passes == 0 then
        local retry = Instance.new("TextButton")
        retry.Size = UDim2.new(1, -UIx.Spacing.SM, 0, UIx.Size.ROW_SECTION)
        retry.Position = UDim2.new(0, UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
        retry.BackgroundColor3 = Theme.colors.Surface
        retry.BackgroundTransparency = Theme.button and Theme.button.surfaceTransparency or 0.1
        retry.Text = "Unable to load passes - RETRY"
        retry.TextScaled = true
        retry.Font = Theme.fonts.Primary
        retry.TextColor3 = Theme.colors.Text
        retry.Parent = gridScroll
        retry.Activated:Connect(function()
            self:refresh()
        end)
        return
    end

    -- Build final entries (gamepasses only)
    local entries = {}
    do
        local seen: {[string]: boolean} = {}
        for _, gp in ipairs(passes) do
            if type(gp.id) == "string" and not seen[gp.id] then
                seen[gp.id] = true
                table.insert(entries, {
                    id = gp.id,
                    gamepassId = gp.gamepassId,
                    name = gp.name or UIUtils.humanize(gp.id or tostring(gp.gamepassId) or "Pass"),
                    priceRobux = tonumber(gp.robux) or 0,
                    owned = gp.owned == true,
                    icon = gp.icon, -- provided by server when available
                })
            end
        end
    end
    -- Stable sort by name for predictability
    table.sort(entries, function(a, b) return tostring(a.name) < tostring(b.name) end)

    local PassDetailsPopup = require(script.Parent:WaitForChild("PassDetailsPopup"))

    for _, entry in ipairs(entries) do
        local priceRobux = tonumber(entry.priceRobux) or 0
        local configured = (type(entry.gamepassId) == "number" and entry.gamepassId > 0)
        local owned = entry.owned == true
        local canBuy = configured and (not owned)

        local item = {
            id = "pass_" .. tostring(entry.id),
            name = entry.name,
            type = "gamepass",
            slot = "pass",
            rarity = nil,
            icon = entry.icon or "",
        }

        ShopGridHelpers.renderItemCell({
            parent = gridScroll,
            item = item,
            rarityEffects = false,
            nameAlign = "center",
            useRarityColorForName = false,
            ownedCount = owned and 1 or 0,
            onTileClick = function()
                local parentGui = (_G and _G.UIManager and _G.UIManager.overlayGui) or self.container
                PassDetailsPopup.new({ parent = parentGui, passId = entry.id })
            end,
            price = priceRobux,
            currencyIcon = "R$",
            canBuy = canBuy,
            onPurchase = function()
                local SoundManager = require(MiningGame:WaitForChild("SoundManager"))
                SoundManager.PlayUI("buttonclick")
                if not configured then
                    if _G.UIManager then _G.UIManager:showNotification("Not for sale", "error") end
                    log:warn("Click ignored: pass not configured id=%s (gamepassId=%s)", tostring(entry.id), tostring(entry.gamepassId))
                    return
                end
                log:info("Purchase click: gamepass id=%s (gamepassId=%s)", tostring(entry.id), tostring(entry.gamepassId))
                local r, e = ClientRF.call("PurchaseGamepass", entry.id)
                if _G.UIManager then
                    if r and r.success then _G.UIManager:showNotification("Purchase prompt opened", "info")
                    else _G.UIManager:showNotification(e or "Purchase failed", "error") end
                end
                if not (r and r.success) then
                    log:warn("Purchase RF failed id=%s reason=%s err=%s", tostring(entry.id), (r and r.reason) or "", tostring(e))
                end
            end,
        })
    end

    -- Support: Render Donate (Developer Product) once, if available via GetPrices
    do
        local ok, res = pcall(function()
            return ClientRF.call("GetPrices")
        end)
        local donate
        if ok and res and res.prices then
            donate = res.prices.DONATE
        end
        if donate and tonumber(donate.price) and tonumber(donate.price) > 0 then
            local priceRobux = tonumber(donate.price) or 0
            local item = {
                id = "product_DONATE",
                name = donate.name or "Donate",
                type = "product",
                slot = "product",
                rarity = nil,
                icon = donate.icon or "",
            }

            ShopGridHelpers.renderItemCell({
                parent = gridScroll,
                item = item,
                rarityEffects = false,
                nameAlign = "center",
                useRarityColorForName = false,
                -- no ownership badge for donate product
                onTileClick = nil,
                price = priceRobux,
                currencyIcon = "R$",
                canBuy = true,
                onPurchase = function()
                    local SoundManager = require(MiningGame:WaitForChild("SoundManager"))
                    SoundManager.PlayUI("buttonclick")
                    log:info("Purchase click: product id=DONATE")
                    local r, e = ClientRF.call("PurchaseProduct", "DONATE")
                    if _G.UIManager then
                        if r and r.success then _G.UIManager:showNotification("Purchase prompt opened", "info")
                        else _G.UIManager:showNotification(e or "Purchase failed", "error") end
                    end
                end,
            })
        end
    end
end

return CashShopCoinsTab
