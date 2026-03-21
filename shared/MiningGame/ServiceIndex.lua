--!strict
-- ServiceIndex.lua (shared)
-- Type-only registry mapping service names to their module interfaces.
-- This lives in ReplicatedStorage so both server and client can import types.

export type ServiceName =
	"RemoteEventBridge"
	| "ErrorService"
	| "DataService"
	| "SessionService"
	| "MixedMaterialService"
	| "GridService"
	| "RemoteManager"
	| "CurrencyService"
	| "AchievementService"
	| "AnnouncementService"
	| "LootService"
	| "UpgradeService"
	| "InventoryService"
	| "ItemService"
	| "MonetizationService"
	| "ThemeSettingsService"
	| "CubePositionService"
	| "WorldGenerationService"
	| "TreeGenerationService"
	| "RockGenerationService"
	| "FireflyGenerationService"
	| "FloatingIslandService"
	| "CubeMaterialService"
	| "CompositionService"
	| "GlowBarService"
	| "PlayerBaseService"
	| "BannerService"
	| "PedestalService"
	| "DigService"
	| "SpawnService"
	| "CharacterStateManager"
	| "TeleportService"
	| "PerkService"
	| "CubeManager"
	| "UserMetricsService"
	| "SimAgents"
	| "RateLimitService"

-- Minimal managed service lifecycle shape (server modules implement this)
export type ManagedService = {
	Init: ((ManagedService, any) -> ())?,
	Start: ((ManagedService, any) -> ())?,
	Stop: ((ManagedService) -> ())?,
}

-- Services map is intentionally loose on the value side to avoid runtime requires here.
-- It is used primarily for typing `ServiceContainer.Get/tryGet` and DI helpers.
export type Services = { [ServiceName]: ManagedService }

return {}
