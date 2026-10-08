--!strict
local Types = require(script.Parent.Types)

local Config = {
	-- Player profile defaults
	DATA_VERSION = 1, -- Profile schema version (stored in profile.Version, upgraded on load). NOT part of the DataStore name.
	AUTOSAVE_INTERVAL_SECONDS = 180,
	STUDIO_MOCK_DATASTORE = true, -- Falls back to in-memory profile if DataStore is disabled in Studio

	-- Persistence & session locking (see docs/ARCHITECTURE.md section 3)
	DATASTORE = {
		-- Fixed name: never derive it from DATA_VERSION, or every player would restart from scratch.
		-- Legacy saves (before session locking) live under this exact name.
		NAME = "MonsterIslands_PlayerData_v1",
		LOAD_MAX_ATTEMPTS = 5, -- DataStore read errors tolerated before kicking the player
		LOAD_RETRY_DELAY_SECONDS = 2, -- Base delay between retries (multiplied by the attempt number)
		LOCK_WAIT_SECONDS = 20, -- How long a joining player waits for another server to release its lock
		LOCK_STALE_SECONDS = 600, -- A lock not refreshed for this long is considered abandoned (crashed server)
		FINAL_SAVE_MAX_ATTEMPTS = 3, -- Attempts for the releasing save (PlayerRemoving / BindToClose)
		SHUTDOWN_TIMEOUT_SECONDS = 25, -- BindToClose budget (Roblox hard limit is 30 s)
	},

	STARTING_CURRENCY = {
		Coins = 500,
		Gems = 15,
	},

	STARTING_PROGRESSION = {
		Level = 1,
		XP = 0,
	},

	STARTING_MONSTER_SPECIES = "emberfox",

	MAX_TEAM_SIZE = 3,

	-- Plots Configuration
	PLOTS = {
		{
			Id = 1,
			Name = "Starter Island - Clearing",
			CostCoins = 0,
			CostGems = 0,
			RequiredLevel = 1,
			Size = Vector3.new(36, 4, 36),
			WorldPosition = Vector3.new(-45, 2, -45),
			MaxMonstersCapacity = 2,
		},
		{
			Id = 2,
			Name = "Hatchery Meadow",
			CostCoins = 250,
			CostGems = 0,
			RequiredLevel = 1,
			Size = Vector3.new(36, 4, 36),
			WorldPosition = Vector3.new(45, 2, -45),
			MaxMonstersCapacity = 2,
		},
		{
			Id = 3,
			Name = "Breeding Grove",
			CostCoins = 750,
			CostGems = 0,
			RequiredLevel = 2,
			Size = Vector3.new(36, 4, 36),
			WorldPosition = Vector3.new(-45, 2, 45),
			MaxMonstersCapacity = 3,
		},
		{
			Id = 4,
			Name = "Elemental Terraces",
			CostCoins = 1500,
			CostGems = 0,
			RequiredLevel = 3,
			Size = Vector3.new(36, 4, 36),
			WorldPosition = Vector3.new(45, 2, 45),
			MaxMonstersCapacity = 3,
		},
		{
			Id = 5,
			Name = "Elder Sanctuary",
			CostCoins = 3000,
			CostGems = 10,
			RequiredLevel = 5,
			Size = Vector3.new(48, 6, 48),
			WorldPosition = Vector3.new(0, 4, 110),
			MaxMonstersCapacity = 5,
		},
	} :: { Types.PlotConfig },

	-- Breeding parameters (Fast durations for responsive prototype testing)
	BREEDING = {
		DEFAULT_BREED_TIME_SECONDS = 15, -- Quick for vertical slice demo
		DEFAULT_INCUBATE_TIME_SECONDS = 10,
		BASE_MUTATION_CHANCE = 0.08, -- 8% chance to discover a rare/mutated creature
		GENETIC_VARIANCE_RANGE = 2,
	},

	-- Combat parameters
	COMBAT = {
		TURN_TIMEOUT_SECONDS = 20,
		BASE_CRIT_CHANCE = 0.10,
		CRIT_DAMAGE_MULTIPLIER = 1.5,
		MIN_DAMAGE_VARIANCE = 0.92,
		MAX_DAMAGE_VARIANCE = 1.08,
		ARENA_POSITION = Vector3.new(0, 5, -120),
		VICTORY_REWARDS = {
			Coins = 100,
			XP = 50,
		},
		DEFEAT_REWARDS = {
			Coins = 25,
			XP = 15,
		},
	},

	-- Plot Decoration system
	PLOT_GRID_SIZE = 4,
	DECORATIONS = {
		{
			Id = "Fence_Wood",
			Name = "Rustic Wooden Fence",
			CostCoins = 20,
			Size = Vector3.new(4, 3, 1),
			PrimaryColor = Color3.fromRGB(130, 85, 45),
			SecondaryColor = Color3.fromRGB(90, 60, 30),
		},
		{
			Id = "Lantern_Pillar",
			Name = "Elemental Glow Lantern",
			CostCoins = 50,
			Size = Vector3.new(2, 6, 2),
			PrimaryColor = Color3.fromRGB(70, 70, 80),
			SecondaryColor = Color3.fromRGB(255, 220, 100),
		},
		{
			Id = "Elemental_Flower",
			Name = "Blazing Blossom",
			CostCoins = 35,
			Size = Vector3.new(3, 2, 3),
			PrimaryColor = Color3.fromRGB(240, 80, 50),
			SecondaryColor = Color3.fromRGB(50, 180, 70),
		},
		{
			Id = "Stone_Bench",
			Name = "Mossy Stone Bench",
			CostCoins = 40,
			Size = Vector3.new(4, 2, 2),
			PrimaryColor = Color3.fromRGB(140, 145, 140),
			SecondaryColor = Color3.fromRGB(80, 130, 80),
		},
		{
			Id = "Training_Dummy",
			Name = "Combat Training Dummy",
			CostCoins = 100,
			Size = Vector3.new(3, 5, 3),
			PrimaryColor = Color3.fromRGB(190, 150, 100),
			SecondaryColor = Color3.fromRGB(220, 60, 50),
		},
	} :: { Types.DecorationConfig },

	-- Logging config
	LOG_LEVEL = "INFO", -- "DEBUG" | "INFO" | "WARN" | "ERROR"
}

return Config
