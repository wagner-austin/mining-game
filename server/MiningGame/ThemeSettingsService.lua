--!strict
-- ThemeSettingsService.lua
-- Server-side theme settings validation and persistence

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MG = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MG:WaitForChild("Logger"))
local log = Logger.new("ThemeSettingsService")
local ServiceValidator = require(MG:WaitForChild("ServiceValidator"))
-- No direct remotes wiring here; centralized RemoteManager used

-- Services (injected via Init)
local _DataService

-- Whitelist UI themes from shared packs
local ThemePacks = require(MG:WaitForChild("UI"):WaitForChild("ThemePacks"))
local AllowedUI = {}
for name in pairs(ThemePacks) do
	AllowedUI[name] = true
end

-- Whitelist sound packs by ModuleScript name under shared/MiningGame/SoundPacks
-- Sound packs validation handled in RF layer

-- Service definition
local ThemeSettingsService = {}
ThemeSettingsService.__index = ThemeSettingsService

type ThemeSettingsServiceT = {
	Init: (self: ThemeSettingsServiceT, container: any) -> (),
}

-- Initialize with DI container
function ThemeSettingsService:Init(container)
	_DataService = ServiceValidator.get(container, "DataService", { "GetPlayerData", "QueueSave" })
	log:info("Initialized with dependencies")
end

-- [MIGRATED TO ThemeSettingsServiceRemotes.lua]
-- All remote handlers now use centralized RemoteManager pattern

log:info("Initialized")

return ThemeSettingsService
