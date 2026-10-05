--!strict
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local MonsterDefinitions = require(ReplicatedStorage.Shared.MonsterDefinitions)
local Network = require(ReplicatedStorage.Shared.Utility.Network)

local DATASTORE_NAME = "MonsterIslands_PlayerData_v" .. tostring(Config.DATA_VERSION)
local playerDataStore: DataStore? = nil

local loadedProfiles: { [Player]: Types.PlayerData } = {}
local isStudio = RunService:IsStudio()

local PlayerDataService = {}

local function generateStarterIVs(): Types.MonsterIVs
	return {
		Health = math.random(6, 12),
		Attack = math.random(6, 12),
		Defense = math.random(6, 12),
		Speed = math.random(6, 12),
	}
end

local function createDefaultProfile(): Types.PlayerData
	local starterSpecies = Config.STARTING_MONSTER_SPECIES
	local starterIVs = generateStarterIVs()
	local calculatedStats, maxHealth = MonsterDefinitions.CalculateStats(starterSpecies, 1, starterIVs)
	local starterUUID = HttpService:GenerateGUID(false)

	local starterMonster: Types.MonsterInstance = {
		UUID = starterUUID,
		SpeciesId = starterSpecies,
		Nickname = "Blaze",
		Level = 1,
		XP = 0,
		CurrentHealth = maxHealth,
		MaxHealth = maxHealth,
		IVs = starterIVs,
		CalculatedStats = calculatedStats,
		SkillsEquipped = { "FlameBurst", "QuickStrike" },
		Parents = nil,
		Generation = 1,
		AssignedPlotId = 1,
		CreatedAt = os.time(),
	}

	local plots: { [string]: Types.PlotData } = {}
	for _, plotConfig in ipairs(Config.PLOTS) do
		plots[tostring(plotConfig.Id)] = {
			Id = plotConfig.Id,
			IsUnlocked = (plotConfig.Id == 1), -- Plot 1 is unlocked for free by default
			UnlockedAt = (plotConfig.Id == 1) and os.time() or nil,
			PlacedMonsters = (plotConfig.Id == 1) and { starterUUID } or {},
		}
	end

	local monsters: { [string]: Types.MonsterInstance } = {}
	monsters[starterUUID] = starterMonster

	return {
		Version = Config.DATA_VERSION,
		Currency = {
			Coins = Config.STARTING_CURRENCY.Coins,
			Gems = Config.STARTING_CURRENCY.Gems,
		},
		Progression = {
			Level = Config.STARTING_PROGRESSION.Level,
			XP = Config.STARTING_PROGRESSION.XP,
		},
		Monsters = monsters,
		TeamMonsterUUIDs = { starterUUID },
		Plots = plots,
		BreedingSessions = {},
		Inventory = {
			["Potion_Health_Small"] = 3,
			["Berry_Fire"] = 5,
		},
		LastSaveTimestamp = os.time(),
	}
end

function PlayerDataService:Init()
	Logger:Info("DATA", "Initializing PlayerDataService...")

	if not isStudio or not Config.STUDIO_MOCK_DATASTORE then
		local success, store = pcall(function()
			return DataStoreService:GetDataStore(DATASTORE_NAME)
		end)
		if success then
			playerDataStore = store
			Logger:Info("DATA", "DataStore '%s' successfully connected", DATASTORE_NAME)
		else
			Logger:Warn("DATA", "Failed to connect to DataStore (likely offline or API disabled in Studio)")
		end
	else
		Logger:Info("DATA", "Studio mock DataStore active: in-memory profile persistence enabled")
	end

	-- Network handlers
	Network.HandleFunction("GetPlayerData", function(player: Player)
		return self:GetProfile(player)
	end)
end

function PlayerDataService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:_loadPlayerProfile(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_savePlayerProfile(player)
		loadedProfiles[player] = nil
	end)

	game:BindToClose(function()
		Logger:Info("DATA", "Server closing, saving all active player profiles...")
		for player, _ in pairs(loadedProfiles) do
			self:_savePlayerProfile(player)
		end
	end)

	-- Periodic autosave
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_INTERVAL_SECONDS)
			Logger:Debug("DATA", "Running periodic autosave cycle...")
			for player, _ in pairs(loadedProfiles) do
				if player.Parent then
					self:_savePlayerProfile(player)
				end
			end
		end
	end)

	-- Handle already connected players (e.g. fast Studio startup)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:_loadPlayerProfile(player)
		end)
	end
end

function PlayerDataService:_loadPlayerProfile(player: Player)
	local userId = player.UserId
	local profile: Types.PlayerData? = nil

	if playerDataStore then
		local key = "User_" .. tostring(userId)
		local success, result = pcall(function()
			return playerDataStore:GetAsync(key)
		end)
		if success and result then
			profile = result :: Types.PlayerData
			Logger:Info("DATA", "Loaded remote profile for player %s (%d)", player.Name, userId)
		end
	end

	if not profile then
		profile = createDefaultProfile()
		Logger:Info("DATA", "Created initial default profile for player %s (%d)", player.Name, userId)
	end

	loadedProfiles[player] = profile :: Types.PlayerData

	-- Broadcast initial profile state to client
	Network.FireClient("PlayerDataLoaded", player, profile)
end

function PlayerDataService:_savePlayerProfile(player: Player)
	local profile = loadedProfiles[player]
	if not profile then return end

	profile.LastSaveTimestamp = os.time()

	if playerDataStore then
		local key = "User_" .. tostring(player.UserId)
		local success, err = pcall(function()
			playerDataStore:SetAsync(key, profile)
		end)
		if success then
			Logger:Info("DATA", "Saved profile for player %s (%d)", player.Name, player.UserId)
		else
			Logger:Error("DATA", "Failed to save profile for player %s: %s", player.Name, tostring(err))
		end
	else
		Logger:Debug("DATA", "Mock profile updated in-memory for player %s", player.Name)
	end
end

function PlayerDataService:GetProfile(player: Player): Types.PlayerData?
	return loadedProfiles[player]
end

function PlayerDataService:UpdateProfile(player: Player, updater: (profile: Types.PlayerData) -> ()): boolean
	local profile = loadedProfiles[player]
	if not profile then
		Logger:Warn("DATA", "Cannot update profile: Player %s has no active profile", player.Name)
		return false
	end

	local ok, err = pcall(updater, profile)
	if not ok then
		Logger:Error("DATA", "Error running updater on player %s: %s", player.Name, tostring(err))
		return false
	end

	-- Sync changes to client
	Network.FireClient("PlayerDataUpdated", player, profile)
	return true
end

return PlayerDataService
