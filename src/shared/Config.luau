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
	STARTING_MONSTER_NICKNAME = "Blaze",

	-- Second starter monster (issue #16): breeding needs two monsters, so every player also gets one
	-- of these, drawn at random. Only species breeding-compatible with the starter in BOTH parent
	-- orders belong here (the breeding UI picks parents in arbitrary order): aquaphin is left out
	-- because emberfox does not accept Water (see StarterMonsters / BreedingMath.AreCompatible).
	SECOND_STARTER_POOL = {
		{ SpeciesId = "mossaur", Nickname = "Moss" },
		{ SpeciesId = "zephlyn", Nickname = "Gust" },
	} :: { { SpeciesId: string, Nickname: string } },
	STARTER_IV_RANGE = { Min = 6, Max = 12 }, -- IVs rolled for both starters

	MAX_TEAM_SIZE = 3,

	-- Per-player plot islands (issue #21): every player is given one slot (an annex island linked
	-- to the hub by a bridge) when joining, holding their own copy of PLOTS. Freed when they leave.
	PLOT_SLOTS = {
		MAX_SLOTS = 8, -- Keep the place's "Max Players" <= this value; extra players get no island
		RING_RADIUS = 250, -- Hub center -> island center distance (>= ~230 to avoid island overlap with 8 slots)
		RING_ANGLE_OFFSET_DEGREES = 22.5, -- Keeps islands and bridges clear of the arena (N) and sanctuary (W)
		ISLAND_SIZE = Vector3.new(112, 4, 160), -- Must contain every PLOTS entry (LocalPosition +/- Size / 2)
		BRIDGE_START_RADIUS = 12, -- Bridges start next to the village spawn
		BRIDGE_WIDTH = 8,
		SPAWN_LOCAL_POSITION = Vector3.new(0, 5, 19), -- Island plaza, between the plot rows and plot 5
		OWNER_SIGN_LOCAL_POSITION = Vector3.new(-12, 2, 19), -- Base of the "<name>'s Island" post, on the plaza
		-- Per-island breeding nest (issue #29): the owner's eggs incubate here. Free east corner, beside
		-- plot 5 and clear of the plaza and of every bridge landing (checked by the unit tests).
		NEST_LOCAL_POSITION = Vector3.new(40, 2, 44), -- Center of the nest base, at island top level
		NEST_SIZE = Vector3.new(12, 1.5, 12),
		NEST_EGG_SPREAD_RADIUS = 3.5, -- Eggs are laid at most this far from the nest center
		TELEPORT_ON_FIRST_SPAWN = true,
	},

	-- Plots Configuration (LocalPosition is relative to the owner's slot origin, island top at y = 2)
	PLOTS = {
		{
			Id = 1,
			Name = "Starter Island - Clearing",
			CostCoins = 0,
			CostGems = 0,
			RequiredLevel = 1,
			Size = Vector3.new(36, 4, 36),
			LocalPosition = Vector3.new(-24, 2, -54),
			MaxMonstersCapacity = 2,
		},
		{
			Id = 2,
			Name = "Hatchery Meadow",
			CostCoins = 250,
			CostGems = 0,
			RequiredLevel = 1,
			Size = Vector3.new(36, 4, 36),
			LocalPosition = Vector3.new(24, 2, -54),
			MaxMonstersCapacity = 2,
		},
		{
			Id = 3,
			Name = "Breeding Grove",
			CostCoins = 750,
			CostGems = 0,
			RequiredLevel = 2,
			Size = Vector3.new(36, 4, 36),
			LocalPosition = Vector3.new(-24, 2, -6),
			MaxMonstersCapacity = 3,
		},
		{
			Id = 4,
			Name = "Elemental Terraces",
			CostCoins = 1500,
			CostGems = 0,
			RequiredLevel = 3,
			Size = Vector3.new(36, 4, 36),
			LocalPosition = Vector3.new(24, 2, -6),
			MaxMonstersCapacity = 3,
		},
		{
			Id = 5,
			Name = "Elder Sanctuary",
			CostCoins = 3000,
			CostGems = 10,
			RequiredLevel = 5,
			Size = Vector3.new(48, 6, 48),
			LocalPosition = Vector3.new(0, 4, 50),
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

	-- Player progression curve (issue #17), used by ProgressionMath / PlayerDataService:AddPlayerXP.
	-- XP to go from level L to L+1 = BASE_XP_TO_LEVEL_UP + XP_INCREMENT_PER_LEVEL * (L - 1)
	--   L1->2: 120, L2->3: 180, L3->4: 240, L4->5: 300  =>  cumulative: Lv2 120, Lv3 300, Lv4 540, Lv5 840.
	-- Rationale (rewards: victory 50 XP, defeat 15 XP, quests 50/75/100 XP once each):
	--   * level 2 (plot 3) after 2-3 victories (100-150 XP), or 1 victory + a quest;
	--   * level 5 (plot 5) after ~12 victories plus the 3 starter quests (840 - 225 = 615 XP), i.e. one
	--     reasonable play session; a linear increment keeps later levels slower without a steep wall.
	PROGRESSION = {
		BASE_XP_TO_LEVEL_UP = 120,
		XP_INCREMENT_PER_LEVEL = 60,
		MAX_LEVEL = 50, -- At max level the XP stays at 0 (further gains are discarded)
	},

	-- Logging config
	LOG_LEVEL = "INFO", -- "DEBUG" | "INFO" | "WARN" | "ERROR"
}

return Config
