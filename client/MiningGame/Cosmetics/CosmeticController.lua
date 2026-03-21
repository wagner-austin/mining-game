--!strict
-- CosmeticController.lua
-- Registry-driven controller that auto-loads renderers and handles equipment changes

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local CosmeticDefinitions = require(MiningGame:WaitForChild("CosmeticDefinitions"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local Timeout = require(MiningGame:WaitForChild("Timeout"))
local LoadCfg = require(MiningGame:WaitForChild("LoadingConstants"))
local Time = require(MiningGame:WaitForChild("Time"))
local Bus = EventBus.global()
-- Use the ClientError handler from PlayerScripts so this module (under ReplicatedStorage) can access it reliably
local ClientError = require(MiningGame:WaitForChild("ClientError"))

-- Type definitions for RF responses
type ItemsBySlot = { [string]: string }
type AllEquipped = { [string]: { [string]: string } }
type EquipResponse = { success: boolean, reason: string? }
local function RF_GetEquippedItems(): (ItemsBySlot?, string?)
	local data, err = ClientRF.call("GetEquippedItems")
	if type(data) == "table" then
		return data, nil
	end
	return nil, err
end

local function RF_GetAllEquipped(): (AllEquipped?, string?)
	local data, err = ClientRF.call("GetAllEquipped")
	if type(data) == "table" then
		return data, nil
	end
	return nil, err
end

-- Equip/Unequip helpers are currently unused; remove to satisfy lint

local log = Logger.new("CosmeticController")
local CosmeticsFolder = script.Parent
local RendererRegistry = require(CosmeticsFolder:WaitForChild("RendererRegistry"))
type RendererCtx = RendererRegistry.RendererCtx
local RenderersFolder = CosmeticsFolder:WaitForChild("Renderers")

local CosmeticController = {}
CosmeticController._enabled = true
CosmeticController._appliedCosmetics = {}
CosmeticController._connections = {}
CosmeticController._preloadCache = {} -- Track preloaded assets
CosmeticController._slotVersion = {} -- [player][slot] = version number for staleness check
CosmeticController._didInitialSyncLocal = false -- one-time local sync guard

type CosmeticControllerAPI = {
	init: (self: CosmeticControllerAPI) -> (),
	initialSyncLocal: (self: CosmeticControllerAPI) -> (),
	enable: (self: CosmeticControllerAPI) -> (),
	disable: (self: CosmeticControllerAPI) -> (),
	toggle: (self: CosmeticControllerAPI) -> boolean,
	cleanup: (self: CosmeticControllerAPI) -> (),
}

-- Helper: preload cosmetic assets with timeout
local function preloadCosmeticAsset(instances: { Instance }, showPlaceholder: (() -> ())?): boolean
	-- Skip empty preloads (PreloadAsync can throw on empty arrays)
	if not instances or #instances == 0 then
		return true
	end

	-- Validate, dedupe, and filter to ensure only valid Instances
	local seen, filtered = {}, {}
	for _, inst in ipairs(instances) do
		if typeof(inst) == "Instance" and inst.Parent and not seen[inst] then
			seen[inst] = true
			table.insert(filtered, inst)
		end
	end

	if #filtered == 0 then
		return true -- Nothing to preload
	end

	local t = LoadCfg.TIMEOUTS.CosmeticClient
	local t0 = Time.mono()

	local ok = Timeout.run(function()
		ContentProvider:PreloadAsync(filtered)
	end, t, LoadCfg.POLL_INTERVALS.Default)

	local dt = Time.mono() - t0

	if not ok then
		log:debug("Cosmetic preload timeout (%.1fs) - showing placeholder", t)
		if showPlaceholder then
			showPlaceholder()
		end
		return false
	end

	-- Warn on slow loads (non-timeout)
	if dt > 0.5 then
		log:warn("Slow cosmetic preload (%.2fs) for %d assets", dt, #filtered)
	end

	return true
end

-- Auto-load all renderer modules
local function loadRenderers()
	-- Static require to load and register all renderers
	local ok, res = ClientError.try("Cosmetics.RenderersInit", function()
		-- Explicitly require each renderer; they self-register in the registry
		require(RenderersFolder:WaitForChild("Aura"))
		require(RenderersFolder:WaitForChild("Back"))
		require(RenderersFolder:WaitForChild("Hand"))
		require(RenderersFolder:WaitForChild("Head"))
		require(RenderersFolder:WaitForChild("Trail"))
		return true
	end)
	if ok then
		log:info(
			"Renderers initialized (count=%d)",
			require(RenderersFolder.Parent:WaitForChild("RendererRegistry")).count()
		)
	else
		log:warn("Failed to initialize renderers: %s", tostring(res))
	end
end

-- Apply cosmetics to a character
local function applyCosmetics(player: Player, equipped: { [string]: string })
	-- Debug: Log what's being equipped
	log:debug("Applying cosmetics for %s", player.Name)
	for slot, itemId in pairs(equipped) do
		log:debug("  - %s : %s", tostring(slot), tostring(itemId))
	end
	local character = player.Character
	if not character then
		return
	end

	-- All cosmetics re-enabled after fixing Aura renderer
	-- The issue was in Aura.lua setting CFrame after creating the weld

	-- Clean up existing cosmetics for this player
	CosmeticController._appliedCosmetics[player] = CosmeticController._appliedCosmetics[player] or {}
	-- Clear any existing state for this player first
	local function __removeAll(p: Player)
		local bySlot = CosmeticController._appliedCosmetics[p]
		if not bySlot then
			return
		end
		for slot, ctx in pairs(bySlot) do
			local renderer = RendererRegistry.get(slot)
			if renderer and renderer.remove then
				local _ok, _ = ClientError.try(("Cosmetics.RemoveAll:%s"):format(tostring(slot)), function()
					renderer.remove(ctx)
					return true
				end)
			end
		end
		CosmeticController._appliedCosmetics[p] = {}
		CosmeticController._slotVersion[p] = {}
	end
	__removeAll(player)

	-- Create player entry if needed
	if not CosmeticController._appliedCosmetics[player] then
		CosmeticController._appliedCosmetics[player] = {}
	end

	-- Initialize slot versions for staleness checking
	CosmeticController._slotVersion[player] = CosmeticController._slotVersion[player] or {}

	-- Sort items by renderer priority
	local sortedItems = {}
	for slot, itemId in pairs(equipped) do
		local renderer = RendererRegistry.get(slot)
		if renderer then
			table.insert(sortedItems, {
				slot = slot,
				itemId = itemId,
				priority = renderer.priority or 0,
			})
		end
	end
	table.sort(sortedItems, function(a, b)
		return a.priority > b.priority
	end)

	-- Apply cosmetics in priority order
	for _, item in ipairs(sortedItems) do
		local renderer = RendererRegistry.get(item.slot)
		if renderer then
			local itemDef = CosmeticDefinitions.Get(item.itemId)
			if itemDef then
				-- Increment slot version for staleness check
				local version = (CosmeticController._slotVersion[player][item.slot] or 0) + 1
				CosmeticController._slotVersion[player][item.slot] = version

				-- Preload assets if not cached (consider variant for cache key)
				local key = item.itemId .. ":" .. (itemDef.variant or "default")
				if not CosmeticController._preloadCache[key] then
					-- Let renderer provide assets to preload (optional, wrapped in pcall)
					local toPreload = {}
					if renderer.preload and type(renderer.preload) == "function" then
						local okPre, assets = ClientError.try(
							("Cosmetics.Preload:%s:%s"):format(tostring(item.slot), tostring(item.itemId)),
							function()
								return renderer.preload(itemDef, character)
							end
						)
						if okPre and assets then
							toPreload = assets
						end
					end

					-- Preload with timeout and optional placeholder
					preloadCosmeticAsset(toPreload, function()
						if renderer.showPlaceholder then
							ClientError.try(
								("Cosmetics.PlaceholderShow:%s:%s"):format(tostring(item.slot), tostring(item.itemId)),
								function()
									renderer.showPlaceholder(character, itemDef)
									return true
								end
							)
						end
					end)
					CosmeticController._preloadCache[key] = true
				end

				-- Apply cosmetic asynchronously to avoid blocking
				task.spawn(function()
					-- Race condition guards
					if not character or not character.Parent then
						return
					end
					if not CosmeticController._appliedCosmetics[player] then
						return
					end

					-- Check if slot is still current
					if CosmeticController._slotVersion[player][item.slot] ~= version then
						return -- Slot changed, skip stale apply
					end

					local success, result = ClientError.try(
						("Cosmetics.Apply:%s:%s"):format(tostring(item.slot), tostring(item.itemId)),
						function()
							return renderer.apply(character, itemDef)
						end
					)
					if success then
						-- Double-check staleness after apply
						if CosmeticController._slotVersion[player][item.slot] ~= version then
							-- Became stale during apply, clean up
							if renderer.remove then
								ClientError.try(
									("Cosmetics.RemoveStale:%s:%s"):format(tostring(item.slot), tostring(item.itemId)),
									function()
										renderer.remove(result)
										return true
									end
								)
							end
							-- Hide placeholder if renderer supports it
							if renderer.hidePlaceholder then
								ClientError.try(
									("Cosmetics.PlaceholderHide:%s:%s"):format(
										tostring(item.slot),
										tostring(item.itemId)
									),
									function()
										renderer.hidePlaceholder(character)
										return true
									end
								)
							end
							return
						end

						CosmeticController._appliedCosmetics[player][item.slot] = result
						log:debug("Applied %s to %s", item.itemId, player.Name)

						-- Hide placeholder on successful apply
						if renderer.hidePlaceholder then
							ClientError.try(
								("Cosmetics.PlaceholderHide:%s:%s"):format(tostring(item.slot), tostring(item.itemId)),
								function()
									renderer.hidePlaceholder(character)
									return true
								end
							)
						end
					else
						log:warn("Failed to apply %s: %s", item.itemId, tostring(result))
					end
				end)
			else
				log:warn("Unknown cosmetic: %s", item.itemId)
			end
		else
			log:debug("No renderer for slot: %s", item.slot)
		end
	end
end

-- Remove all cosmetics from a player
local function removeAllCosmetics(player: Player)
	local playerCosmetics = CosmeticController._appliedCosmetics[player]
	if not playerCosmetics then
		return
	end

	for slot, ctx in pairs(playerCosmetics) do
		local renderer = RendererRegistry.get(slot)
		if renderer and renderer.remove then
			local ok, err = ClientError.try(("Cosmetics.RemoveAll:%s"):format(tostring(slot)), function()
				renderer.remove(ctx)
				return true
			end)
			if not ok then
				log:warn("Error removing %s: %s", slot, tostring(err))
			end
		end
	end

	CosmeticController._appliedCosmetics[player] = {}
	CosmeticController._slotVersion[player] = {} -- Invalidate any in-flight applies
end

-- Handle equipment changes
local function removeSlot(player: Player, slot: string)
	local bySlot = CosmeticController._appliedCosmetics[player]
	if not bySlot then
		return
	end

	-- Bump version so any pending apply for this slot is considered stale
	CosmeticController._slotVersion[player] = CosmeticController._slotVersion[player] or {}
	CosmeticController._slotVersion[player][slot] = (CosmeticController._slotVersion[player][slot] or 0) + 1

	local ctx = bySlot[slot]
	if not ctx then
		return
	end

	local renderer = RendererRegistry.get(slot)
	if not renderer or not renderer.remove then
		return
	end

	local ok, err = ClientError.try(("Cosmetics.Remove:%s"):format(tostring(slot)), function()
		renderer.remove(ctx)
		return true
	end) -- remove(ctx) only, no character arg
	if not ok then
		log:warn("Remove %s failed: %s", slot, tostring(err))
	end
	bySlot[slot] = nil
end

local function applySingleSlot(player: Player, slot: string, itemId: string)
	local character = player.Character
	if not character then
		return
	end

	local renderer = RendererRegistry.get(slot)
	if not renderer then
		return
	end

	local def = CosmeticDefinitions.Get(itemId)
	if not def then
		return
	end

	-- Clear old ctx for this slot
	removeSlot(player, slot)

	-- Apply
	local ok, ctx = ClientError.try(("Cosmetics.ApplySingle:%s"):format(tostring(slot)), function()
		return renderer.apply(character, def)
	end)
	if ok then
		CosmeticController._appliedCosmetics[player] = CosmeticController._appliedCosmetics[player] or {}
		CosmeticController._appliedCosmetics[player][slot] = ctx
	else
		log:warn("Apply %s failed: %s", itemId, tostring(ctx))
	end
end

-- Handle character spawning
local function onCharacterAdded(player: Player)
	-- Clean up any previous character data
	removeAllCosmetics(player)
	CosmeticController._slotVersion[player] = {} -- Reset slot versions on respawn

	-- Wait for character to load
	local character = player.Character
	if not character then
		return
	end

	local _hrp = character:WaitForChild("HumanoidRootPart")
	character:WaitForChild("Humanoid")

	-- Request and apply this player's equipment
	task.spawn(function()
		local equipped
		if player == Players.LocalPlayer then
			log:debug("Getting equipped items for local player")
			local _err
			equipped, _err = RF_GetEquippedItems()
			log:debug("Equipped items: %s", tostring(equipped))
		else
			local all
			local _errAll
			all, _errAll = RF_GetAllEquipped()
			equipped = all and all[tostring(player.UserId)]
		end

		if equipped and CosmeticController._enabled then
			applyCosmetics(player, equipped)
		else
			log:debug("No equipped items or controller disabled")
		end
	end)
end

-- Handle player removing
local function onPlayerRemoving(player: Player)
	removeAllCosmetics(player)
	CosmeticController._appliedCosmetics[player] = nil
	CosmeticController._slotVersion[player] = nil -- Clean up slot versions
	if player == Players.LocalPlayer then
		CosmeticController._didInitialSyncLocal = false
	end
end

-- Initialize the controller
local function init()
	-- Load all renderer modules
	loadRenderers()

	local _localPlayer = Players.LocalPlayer

	-- Listen for equipment changes from any player (EventBus)
	local offEquip = Bus:on(EventNames.EQUIPMENT_CHANGED, function(payload)
		if not payload or not payload.playerUserId or not payload.slot then
			return
		end

		local p = Players:GetPlayerByUserId(payload.playerUserId)
		if not p then
			return
		end

		-- If a model swap changed, rebuild layering from scratch for that player
		local _needsRelayer = false -- modelSwap removed

		if payload.itemId then
			-- Only (re)apply this slot
			applySingleSlot(p, payload.slot, payload.itemId)
		else
			removeSlot(p, payload.slot)
		end
	end)
	table.insert(CosmeticController._connections, offEquip)

	-- Handle character spawning for all players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			onCharacterAdded(player)
		end

		local charConn = player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)
		table.insert(CosmeticController._connections, function()
			if charConn.Connected then
				charConn:Disconnect()
			end
		end)

		local charRemConn = player.CharacterRemoving:Connect(function()
			removeAllCosmetics(player)
		end)
		table.insert(CosmeticController._connections, function()
			if charRemConn.Connected then
				charRemConn:Disconnect()
			end
		end)
	end

	-- Handle new players joining
	local playerAddedConn = Players.PlayerAdded:Connect(function(player)
		local charConn = player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)
		table.insert(CosmeticController._connections, function()
			if charConn.Connected then
				charConn:Disconnect()
			end
		end)

		local charRemConn = player.CharacterRemoving:Connect(function()
			removeAllCosmetics(player)
		end)
		table.insert(CosmeticController._connections, function()
			if charRemConn.Connected then
				charRemConn:Disconnect()
			end
		end)

		if player.Character then
			onCharacterAdded(player)
		end
	end)
	table.insert(CosmeticController._connections, function()
		if playerAddedConn.Connected then
			playerAddedConn:Disconnect()
		end
	end)

	-- Handle players leaving
	local playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
		onPlayerRemoving(player)
	end)
	table.insert(CosmeticController._connections, function()
		if playerRemovingConn.Connected then
			playerRemovingConn:Disconnect()
		end
	end)

	-- Initial sync: get all players' equipped items
	-- COMMENTED OUT: This causes double application since _onCharacterAdded already handles this!
	-- The _onCharacterAdded function is already called for existing players above (line 429)
	-- and it fetches and applies cosmetics. This second application was causing issues.
	--[[
    task.spawn(function()
        local allEquipped, err = Calls.GetAllEquipped()
        
        if not err and allEquipped and self._enabled then
            for userIdRaw, equipped in pairs(allEquipped) do
                -- Properly decode userId from remote payload (keys are serialized as strings)
                local userId = (typeof(userIdRaw) == "number") and userIdRaw or tonumber(userIdRaw)
                assert(userId, ("GetAllEquipped: bad userId key %s"):format(tostring(userIdRaw)))
                
                local player = Players:GetPlayerByUserId(userId)
                if player and player.Character then
                    self:_applyCosmetics(player, equipped)
                end
            end
        elseif err then
            log:warn("Failed to get initial equipped items: %s", err)
        end
    end)
    --]]

	log:info("CosmeticController initialized with %d renderers", RendererRegistry.count())
end

-- One-time initial local sync after readiness
local function initialSyncLocal()
	if CosmeticController._didInitialSyncLocal then
		return
	end
	CosmeticController._didInitialSyncLocal = true
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end
	if CosmeticController._enabled and localPlayer.Character then
		local equipped, _err = RF_GetEquippedItems()
		if type(equipped) == "table" then
			applyCosmetics(localPlayer, equipped)
		end
	end
end

-- Enable cosmetic rendering
local function enable()
	if CosmeticController._enabled then
		return
	end

	CosmeticController._enabled = true
	log:info("Cosmetics enabled")

	-- Re-apply cosmetics to all players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			task.spawn(function()
				local equipped = nil
				if player == Players.LocalPlayer then
					local eq, _err2 = RF_GetEquippedItems()
					equipped = eq
				else
					-- Get from cached data or request fresh
					local allEquipped, _errAll = RF_GetAllEquipped()
					equipped = allEquipped and allEquipped[tostring(player.UserId)]
				end

				if equipped then
					applyCosmetics(player, equipped)
				end
			end)
		end
	end
end

-- Disable cosmetic rendering
local function disable()
	if not CosmeticController._enabled then
		return
	end

	CosmeticController._enabled = false
	log:info("Cosmetics disabled")

	-- Remove all cosmetics from all players
	for player, _ in pairs(CosmeticController._appliedCosmetics) do
		removeAllCosmetics(player)
	end
end

-- Toggle cosmetic rendering
local function toggle()
	if CosmeticController._enabled then
		disable()
	else
		enable()
	end
	return CosmeticController._enabled
end

-- Cleanup
local function cleanup()
	-- Remove all cosmetics
	for player, _ in pairs(CosmeticController._appliedCosmetics) do
		removeAllCosmetics(player)
	end
	CosmeticController._appliedCosmetics = {}

	-- Disconnect all connections (handle both RBXScriptConnections and functions)
	for _, conn in ipairs(CosmeticController._connections) do
		if typeof(conn) == "function" then
			conn() -- EventBus off() function
		else
			local c = conn
			if typeof(c) == "RBXScriptConnection" then
				c:Disconnect()
			end
		end
	end
	CosmeticController._connections = {}
end

-- Hook cleanup to script destroy
if script and script.Destroying then
	script.Destroying:Connect(function()
		cleanup()
	end)
end

local Export: CosmeticControllerAPI = {
	init = function(_self)
		init()
	end,
	initialSyncLocal = function(_self)
		initialSyncLocal()
	end,
	enable = function(_self)
		enable()
	end,
	disable = function(_self)
		disable()
	end,
	toggle = function(_self): boolean
		return toggle()
	end,
	cleanup = function(_self)
		cleanup()
	end,
}

return Export
