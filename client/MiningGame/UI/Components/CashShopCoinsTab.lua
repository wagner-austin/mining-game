-- CashShopCoinsTab.lua - Passes tab (Roblox Gamepasses) styled like Cosmetics: tile + price button row

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))
local ItemTileRenderer = require(script.Parent:WaitForChild("ItemTileRenderer"))
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

    -- Card container (match Cosmetics sizing: full-height card with scrollable grid inside)
    local card = self:createSectionCard(self.container, { name = "PassesCard", size = UDim2.new(1, 0, 1, -UIx.Size.ROW_LARGE), autoSize = false })
    self:createSectionTitle(card, "Passes")

    local gridScroll = Instance.new("ScrollingFrame")
    gridScroll.Name = "Grid"
    gridScroll.Size = UDim2.new(1, 0, 1, -UIx.Size.BUTTON_SMALL_HEIGHT)
    gridScroll.Position = UDim2.new(0, 0, 0, UIx.Size.ROW_LARGE)
    gridScroll.BackgroundTransparency = 1
    gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    gridScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    gridScroll.CanvasSize = UIx.Common.ORIGIN
    gridScroll.Parent = card

    local layout = Instance.new("UIGridLayout")
    -- Match Cosmetics: add extra height to fit price row below tile
    layout.CellSize = UDim2.new(0, UIx.Size.INVENTORY_CELL_WIDTH, 0, UIx.Size.INVENTORY_CELL_HEIGHT + UIx.Size.ROW_STANDARD + UIx.Spacing.SM + 2)
    layout.CellPadding = UDim2.new(0, UIx.Spacing.SM, 0, UIx.Spacing.SM)
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = gridScroll

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
                })
            end
        end
    end

    for _, entry in ipairs(entries) do
        local priceRobux = tonumber(entry.priceRobux) or 0
        local item = {
            id = "pass_" .. tostring(entry.id),
            name = entry.name,
            type = "gamepass",
            slot = "pass",
            rarity = nil,
            icon = "",
        }

        -- Cell container (tile + price row)
        local cell = Instance.new("Frame")
        cell.Name = "ShopCell"
        cell.BackgroundTransparency = 1
        cell.Size = UDim2.new(1, 0, 1, 0)
        cell.Parent = gridScroll
        local vlayout = Instance.new("UIListLayout")
        vlayout.FillDirection = Enum.FillDirection.Vertical
        vlayout.Padding = UDim.new(0, UIx.Spacing.TINY)
        vlayout.SortOrder = Enum.SortOrder.LayoutOrder
        vlayout.Parent = cell

        -- Tile area (fixed height)
        local tileHost = Instance.new("Frame")
        tileHost.Name = "TileHost"
        tileHost.BackgroundTransparency = 1
        tileHost.Size = UDim2.new(1, 0, 0, UIx.Size.INVENTORY_CELL_HEIGHT)
        tileHost.LayoutOrder = 1
        tileHost.Parent = cell

        local tile = ItemTileRenderer.create({
            item = item,
            parent = tileHost,
            sizeMode = "fixed",
            fixedSize = UDim2.new(1, 0, 0, UIx.Size.INVENTORY_CELL_HEIGHT),
            rarityEffects = false,
        })
        local btnTile = tile.button
        tile.helpers.addSymbol(item)
        tile.helpers.addNameLabel(item.name, { useRarityColor = false, align = "center" })
        btnTile.Active = true

        -- Price row below tile
        local priceRow = Instance.new("Frame")
        priceRow.Name = "PriceRow"
        priceRow.BackgroundTransparency = 1
        priceRow.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_STANDARD + 2)
        priceRow.LayoutOrder = 2
        priceRow.Parent = cell

        local priceBtn = Instance.new("TextButton")
        priceBtn.Name = "PriceButton"
        priceBtn.AutoButtonColor = true
        priceBtn.AnchorPoint = Vector2.new(0.5, 0)
        priceBtn.Position = UDim2.new(0.5, 0, 0, 0)
        priceBtn.Size = UDim2.new(0, math.min(84, UIx.Size.INVENTORY_CELL_WIDTH - UIx.Spacing.SM*2), 1, 0)
        priceBtn.BackgroundColor3 = Theme.colors.Background
        priceBtn.BackgroundTransparency = 0.1
        priceBtn.Text = ""
        priceBtn.Parent = priceRow
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, UIx.Spacing.MD)
        corner.Parent = priceBtn

        local h = Instance.new("UIListLayout")
        h.FillDirection = Enum.FillDirection.Horizontal
        h.VerticalAlignment = Enum.VerticalAlignment.Center
        h.HorizontalAlignment = Enum.HorizontalAlignment.Center
        h.Padding = UDim.new(0, UIx.Spacing.TINY)
        h.Parent = priceBtn

        -- Left icon label (use Robux currency mark)
        local icon = Instance.new("TextLabel")
        icon.BackgroundTransparency = 1
        icon.Text = "R$"
        icon.Font = Theme.fonts.Secondary
        icon.TextScaled = true
        icon.TextColor3 = Theme.colors.Text
        icon.Size = UDim2.new(0, UIx.Size.ROW_STANDARD - 2, 0, UIx.Size.ROW_STANDARD - 2)
        icon.Parent = priceBtn

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Text = UIUtils.formatNumber(priceRobux)
        lbl.Font = Theme.fonts.Secondary
        lbl.TextScaled = true
        lbl.TextColor3 = Theme.colors.Text
        lbl.Size = UDim2.new(1, -UIx.Size.ROW_STANDARD, 1, 0)
        lbl.Parent = priceBtn

        local ThemeRefresher = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("ThemeRefresher"))
        ThemeRefresher.Bind(priceBtn, { BackgroundColor3 = "Background" })
        ThemeRefresher.Bind(icon, { TextColor3 = "Text" })
        ThemeRefresher.Bind(lbl, { TextColor3 = "Text" })

        -- Enablement and click wiring
        local configured = (type(entry.gamepassId) == "number" and entry.gamepassId > 0)
        local owned = entry.owned == true
        local canBuy = configured and (not owned)
        priceBtn.Active = true
        priceBtn.AutoButtonColor = canBuy
        if not canBuy then
            priceBtn.BackgroundTransparency = 0.3
            if owned then
                lbl.Text = "Owned"
            elseif not configured then
                lbl.Text = "Configure"
        end
    end


        priceBtn.Activated:Connect(function()
            local SoundManager = require(MiningGame:WaitForChild("SoundManager"))
            SoundManager.PlayUI("buttonclick")
            if not configured then
                if _G.UIManager then _G.UIManager:showNotification("Pass not configured", "error") end
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
        end)
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

            local cell = Instance.new("Frame")
            cell.Name = "ShopCell_Donate"
            cell.BackgroundTransparency = 1
            cell.Size = UDim2.new(1, 0, 1, 0)
            cell.Parent = gridScroll
            local vlayout = Instance.new("UIListLayout")
            vlayout.FillDirection = Enum.FillDirection.Vertical
            vlayout.Padding = UDim.new(0, UIx.Spacing.TINY)
            vlayout.SortOrder = Enum.SortOrder.LayoutOrder
            vlayout.Parent = cell

            local tileHost = Instance.new("Frame")
            tileHost.Name = "TileHost"
            tileHost.BackgroundTransparency = 1
            tileHost.Size = UDim2.new(1, 0, 0, UIx.Size.INVENTORY_CELL_HEIGHT)
            tileHost.LayoutOrder = 1
            tileHost.Parent = cell

            local tile = ItemTileRenderer.create({
                item = item,
                parent = tileHost,
                sizeMode = "fixed",
                fixedSize = UDim2.new(1, 0, 0, UIx.Size.INVENTORY_CELL_HEIGHT),
                rarityEffects = false,
            })
            tile.helpers.addSymbol(item)
            tile.helpers.addNameLabel(item.name, { useRarityColor = false, align = "center" })

            local priceRow = Instance.new("Frame")
            priceRow.Name = "PriceRow"
            priceRow.BackgroundTransparency = 1
            priceRow.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_STANDARD + 2)
            priceRow.LayoutOrder = 2
            priceRow.Parent = cell

            local priceBtn = Instance.new("TextButton")
            priceBtn.Name = "PriceButton"
            priceBtn.AutoButtonColor = true
            priceBtn.AnchorPoint = Vector2.new(0.5, 0)
            priceBtn.Position = UDim2.new(0.5, 0, 0, 0)
            priceBtn.Size = UDim2.new(0, math.min(84, UIx.Size.INVENTORY_CELL_WIDTH - UIx.Spacing.SM*2), 1, 0)
            priceBtn.BackgroundColor3 = Theme.colors.Background
            priceBtn.BackgroundTransparency = 0.1
            priceBtn.Text = ""
            priceBtn.Parent = priceRow
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, UIx.Spacing.MD)
            corner.Parent = priceBtn

            local h = Instance.new("UIListLayout")
            h.FillDirection = Enum.FillDirection.Horizontal
            h.VerticalAlignment = Enum.VerticalAlignment.Center
            h.HorizontalAlignment = Enum.HorizontalAlignment.Center
            h.Padding = UDim.new(0, UIx.Spacing.TINY)
            h.Parent = priceBtn

            local icon = Instance.new("TextLabel")
            icon.BackgroundTransparency = 1
            icon.Text = "R$"
            icon.Font = Theme.fonts.Secondary
            icon.TextScaled = true
            icon.TextColor3 = Theme.colors.Text
            icon.Size = UDim2.new(0, UIx.Size.ROW_STANDARD - 2, 0, UIx.Size.ROW_STANDARD - 2)
            icon.Parent = priceBtn

            local lbl = Instance.new("TextLabel")
            lbl.BackgroundTransparency = 1
            lbl.Text = UIUtils.formatNumber(priceRobux)
            lbl.Font = Theme.fonts.Secondary
            lbl.TextScaled = true
            lbl.TextColor3 = Theme.colors.Text
            lbl.Size = UDim2.new(1, -UIx.Size.ROW_STANDARD, 1, 0)
            lbl.Parent = priceBtn

            local ThemeRefresher = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("ThemeRefresher"))
            ThemeRefresher.Bind(priceBtn, { BackgroundColor3 = "Background" })
            ThemeRefresher.Bind(icon, { TextColor3 = "Text" })
            ThemeRefresher.Bind(lbl, { TextColor3 = "Text" })

            priceBtn.Activated:Connect(function()
                local SoundManager = require(MiningGame:WaitForChild("SoundManager"))
                SoundManager.PlayUI("buttonclick")
                log:info("Purchase click: product id=DONATE")
                local r, e = ClientRF.call("PurchaseProduct", "DONATE")
                if _G.UIManager then
                    if r and r.success then _G.UIManager:showNotification("Purchase prompt opened", "info")
                    else _G.UIManager:showNotification(e or "Purchase failed", "error") end
                end
            end)
        end
    end
end

return CashShopCoinsTab
