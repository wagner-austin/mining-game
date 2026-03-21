--!strict
-- ServiceIndex.lua
-- Type-only registry mapping service names to their module types.

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

export type Services = {
	RemoteEventBridge: typeof(require(script.Parent.RemoteEventBridge)),
	ErrorService: typeof(require(script.Parent.ErrorService)),
	DataService: typeof(require(script.Parent.DataService)),
	SessionService: typeof(require(script.Parent.SessionService)),
	MixedMaterialService: typeof(require(script.Parent.MixedMaterialService)),
	GridService: typeof(require(script.Parent.GridService)),
	RemoteManager: typeof(require(script.Parent.RemoteManager)),
	CurrencyService: typeof(require(script.Parent.CurrencyService)),
	AchievementService: typeof(require(script.Parent.AchievementService)),
	AnnouncementService: typeof(require(script.Parent.AnnouncementService)),
	LootService: typeof(require(script.Parent.LootService)),
	UpgradeService: typeof(require(script.Parent.UpgradeService)),
	InventoryService: typeof(require(script.Parent.InventoryService)),
	ItemService: typeof(require(script.Parent.ItemService)),
	MonetizationService: typeof(require(script.Parent.MonetizationService)),
	ThemeSettingsService: typeof(require(script.Parent.ThemeSettingsService)),
	CubePositionService: typeof(require(script.Parent.CubePositionService)),
	WorldGenerationService: typeof(require(script.Parent.WorldGenerationService)),
	TreeGenerationService: typeof(require(script.Parent.TreeGenerationService)),
	RockGenerationService: typeof(require(script.Parent.RockGenerationService)),
	FireflyGenerationService: typeof(require(script.Parent.FireflyGenerationService)),
	FloatingIslandService: typeof(require(script.Parent.FloatingIslandService)),
	CubeMaterialService: typeof(require(script.Parent.CubeMaterialService)),
	CompositionService: typeof(require(script.Parent.CompositionService)),
	GlowBarService: typeof(require(script.Parent.GlowBarService)),
	PlayerBaseService: typeof(require(script.Parent.PlayerBaseService)),
	BannerService: typeof(require(script.Parent.BannerService)),
	PedestalService: typeof(require(script.Parent.PedestalService)),
	DigService: typeof(require(script.Parent.DigService)),
	SpawnService: typeof(require(script.Parent.SpawnService)),
	CharacterStateManager: typeof(require(script.Parent.CharacterStateManager)),
	TeleportService: typeof(require(script.Parent.TeleportService)),
	PerkService: typeof(require(script.Parent.PerkService)),
	CubeManager: typeof(require(script.Parent.CubeManager)),
	UserMetricsService: typeof(require(script.Parent.UserMetricsService)),
	SimAgents: typeof(require(script.Parent.SimAgents)),
	RateLimitService: typeof(require(script.Parent.RateLimitService)),
}

return {}
