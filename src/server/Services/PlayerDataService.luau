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

--[[
	Persistence model (issue #20)

	DataStore key "User_<UserId>" holds a StoredRecord:
		{ RecordFormat = 1, Profile = <Types.PlayerData>, SessionLock = { JobId, SessionId, LockedAt }? }
	Saves written before session locking stored the raw profile directly; they are read transparently
	(see decodeRecord) and rewritten in the wrapped format on first load.

	Every read/write goes through UpdateAsync so the lock check and the write are atomic:
	- load:    acquire the lock (refused while another live session holds it), create the profile for
	           new players, retry on errors, kick the player on persistent failure (never a blank profile);
	- save:    only while our session still owns the lock; refreshes LockedAt;
	- release: final save that clears the lock (PlayerRemoving / BindToClose), exactly once per session.
]]

local DS = Config.DATASTORE
local RECORD_FORMAT = 1
local WAIT_POLL_SECONDS = 0.1

type SessionLock = {
	JobId: string,
	SessionId: string,
	LockedAt: number,
}

type StoredRecord = {
	RecordFormat: number,
	Profile: Types.PlayerData,
	SessionLock: SessionLock?,
}

-- Loading -> Active -> Releasing -> Released
-- Loading -> Failed (load error, player kicked)  |  Active -> LockLost (another server took the profile)
type SessionState = "Loading" | "Active" | "Releasing" | "Released" | "Failed" | "LockLost"

type Session = {
	Player: Player,
	UserId: number,
	Key: string,
	SessionId: string,
	Profile: Types.PlayerData?,
	State: SessionState,
	Cancelled: boolean, -- Player left while the profile was still loading
	Saving: boolean, -- A DataStore write is in flight (writes are serialized per session)
}

type PersistenceMode = "DataStore" | "Mock" | "Unavailable"

local playerDataStore: DataStore? = nil
local persistenceMode: PersistenceMode = "Mock"

local loadedProfiles: { [Player]: Types.PlayerData } = {}
local sessions: { [Player]: Session } = {}
local isStudio = RunService:IsStudio()
local isShuttingDown = false

-- game.JobId is empty in Studio: use a fixed id so a lock left by a previous Studio run is
-- recognised as an orphan from "this server" instead of blocking the profile until it goes stale.
local serverId: string = if game.JobId ~= "" then game.JobId else "Studio"

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
			PlacedDecorations = {},
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
		CompletedQuests = {},
		LastSaveTimestamp = os.time(),
	}
end

-- Ensure newer fields exist on existing profiles (fields added after a profile was first saved).
-- Must stay idempotent and non-yielding: it runs inside an UpdateAsync transform.
local function backfillProfile(profile: Types.PlayerData)
	for _, plotData in pairs(profile.Plots) do
		if not plotData.PlacedDecorations then
			plotData.PlacedDecorations = {}
		end
	end
	if not profile.CompletedQuests then
		profile.CompletedQuests = {}
	end
end

-- Schema migrations, keyed by the version they upgrade FROM: MIGRATIONS[1] turns a v1 profile into v2.
-- Bump Config.DATA_VERSION and add a step here when the profile shape changes incompatibly.
-- Steps must be idempotent and non-yielding (they run inside an UpdateAsync transform).
local MIGRATIONS: { [number]: (profile: any) -> () } = {}

-- Upgrades `profile` in place to Config.DATA_VERSION.
-- Returns false for a profile written by a NEWER server version: it must not be loaded (and then
-- saved back) by this older server, which would silently drop the newer fields.
local function migrateProfile(profile: any): boolean
	local version = if typeof(profile.Version) == "number" then profile.Version else 1
	if version > Config.DATA_VERSION then
		return false
	end
	while version < Config.DATA_VERSION do
		local step = MIGRATIONS[version]
		if step then
			step(profile)
		end
		version += 1
	end
	profile.Version = Config.DATA_VERSION
	return true
end

-- Interprets the raw DataStore value. Returns (record, isCorrupt).
-- nil, false  -> key never written (new player)
-- record      -> wrapped record, or a legacy raw profile wrapped on the fly (no lock)
-- nil, true   -> unreadable value: never overwrite it
local function decodeRecord(raw: any): (StoredRecord?, boolean)
	if raw == nil then
		return nil, false
	end
	if typeof(raw) ~= "table" then
		return nil, true
	end
	if raw.Profile ~= nil then
		if typeof(raw.Profile) ~= "table" then
			return nil, true
		end
		local lock = raw.SessionLock
		if lock ~= nil and typeof(lock) ~= "table" then
			lock = nil -- Malformed lock: treat as absent rather than locking the player out forever
		end
		return {
			RecordFormat = tonumber(raw.RecordFormat) or RECORD_FORMAT,
			Profile = raw.Profile,
			SessionLock = lock,
		}, false
	end
	-- Legacy format (before issue #20): the profile itself was stored at the key root.
	if typeof(raw.Plots) == "table" and typeof(raw.Currency) == "table" then
		return { RecordFormat = RECORD_FORMAT, Profile = raw :: any, SessionLock = nil }, false
	end
	return nil, true
end

-- Pure decision: does `lock` prevent session `sessionId` (running on server `ownServerId`) from
-- taking the profile at time `now`? `hasLiveLocalSession` tells whether this server still has
-- another session for the same user (e.g. a quick rejoin while the previous final save is running).
local function isLockBlocking(
	lock: SessionLock?,
	sessionId: string,
	ownServerId: string,
	now: number,
	hasLiveLocalSession: boolean
): boolean
	if lock == nil then
		return false
	end
	if lock.SessionId == sessionId then
		return false -- Our own lock
	end
	if typeof(lock.LockedAt) ~= "number" or now - lock.LockedAt >= DS.LOCK_STALE_SECONDS then
		return false -- Stale: the owning server most likely crashed without releasing it
	end
	if lock.JobId == ownServerId and not hasLiveLocalSession then
		return false -- Orphan lock left by a previous session on this very server
	end
	return true
end

local function waitUntil(predicate: () -> boolean, timeoutSeconds: number): boolean
	local deadline = os.clock() + timeoutSeconds
	while not predicate() do
		if os.clock() >= deadline then
			return false
		end
		task.wait(WAIT_POLL_SECONDS)
	end
	return true
end

local function hasOtherLocalSession(session: Session): boolean
	for _, other in pairs(sessions) do
		if other ~= session and other.UserId == session.UserId then
			return true
		end
	end
	return false
end

-- Terminal states: forget the session (the profile is no longer readable/updatable by gameplay code)
local function closeSession(session: Session, finalState: SessionState)
	session.State = finalState
	if sessions[session.Player] == session then
		sessions[session.Player] = nil
	end
	if loadedProfiles[session.Player] == session.Profile then
		loadedProfiles[session.Player] = nil
	end
end

local function kickForData(session: Session, message: string)
	closeSession(session, "Failed")
	if session.Player.Parent then
		session.Player:Kick(message)
	end
end

type WriteStatus = "Saved" | "LockLost" | "Error"

-- Writes the session profile if (and only if) the session still owns the lock.
-- `release = true` clears the lock in the same atomic write.
local function writeSession(session: Session, release: boolean): WriteStatus
	local store = playerDataStore
	local profile = session.Profile
	if not store or not profile then
		return "Saved"
	end

	session.Saving = true
	local status: WriteStatus = "Error"
	local ok, err = pcall(function()
		(store :: any):UpdateAsync(session.Key, function(current: any): any
			local record = decodeRecord(current)
			local lock = record and record.SessionLock
			if not lock or lock.SessionId ~= session.SessionId then
				status = "LockLost"
				return nil -- Cancel: another server owns this profile now
			end
			local now = os.time()
			profile.LastSaveTimestamp = now
			status = "Saved"
			return {
				RecordFormat = RECORD_FORMAT,
				Profile = profile,
				SessionLock = if release
					then nil
					else { JobId = serverId, SessionId = session.SessionId, LockedAt = now },
			}
		end)
	end)
	session.Saving = false

	if not ok then
		Logger:Error("DATA", "Failed to save profile for player %s: %s", session.Player.Name, tostring(err))
		return "Error"
	end
	return status
end

local function onLockLost(session: Session)
	Logger:Error(
		"DATA",
		"Session lock lost for player %s (%d): another server took the profile, local changes are discarded",
		session.Player.Name,
		session.UserId
	)
	closeSession(session, "LockLost")
	if session.Player.Parent then
		session.Player:Kick("Your save was opened on another server. Please rejoin.")
	end
end

-- Final save + lock release. Idempotent: concurrent callers (PlayerRemoving + BindToClose) wait for
-- the first release instead of writing again.
local function releaseSession(session: Session)
	if session.State == "Loading" then
		session.Cancelled = true -- The loader releases the lock it acquires (see loadSession)
		return
	end
	if session.State == "Releasing" then
		waitUntil(function()
			return session.State ~= "Releasing"
		end, DS.SHUTDOWN_TIMEOUT_SECONDS)
		return
	end
	if session.State ~= "Active" then
		closeSession(session, session.State)
		return
	end

	session.State = "Releasing" -- From now on autosave skips this session
	waitUntil(function()
		return not session.Saving
	end, DS.SHUTDOWN_TIMEOUT_SECONDS)

	if playerDataStore then
		for attempt = 1, DS.FINAL_SAVE_MAX_ATTEMPTS do
			local status = writeSession(session, true)
			if status == "Saved" then
				Logger:Info("DATA", "Saved profile and released lock for player %s (%d)", session.Player.Name, session.UserId)
				break
			elseif status == "LockLost" then
				Logger:Error("DATA", "Final save skipped for player %s: session lock no longer owned", session.Player.Name)
				break
			elseif attempt < DS.FINAL_SAVE_MAX_ATTEMPTS then
				task.wait(DS.LOAD_RETRY_DELAY_SECONDS)
			else
				Logger:Error(
					"DATA",
					"Final save failed for player %s (%d): lock stays until it goes stale (%d s)",
					session.Player.Name,
					session.UserId,
					DS.LOCK_STALE_SECONDS
				)
			end
		end
	else
		Logger:Debug("DATA", "Mock profile released in-memory for player %s", session.Player.Name)
	end

	closeSession(session, "Released")
end

type AcquireStatus = "Acquired" | "Locked" | "Corrupt" | "TooNew" | "Error"

-- One atomic attempt to read the profile and take its lock.
local function tryAcquire(session: Session): (AcquireStatus, Types.PlayerData?, boolean, SessionLock?)
	local store = playerDataStore :: DataStore
	local hasLiveLocalSession = hasOtherLocalSession(session)

	local status: AcquireStatus = "Error"
	local profile: Types.PlayerData? = nil
	local isNew = false
	local blockingLock: SessionLock? = nil

	local ok, err = pcall(function()
		(store :: any):UpdateAsync(session.Key, function(current: any): any
			-- The transform may run several times: reset every output on each call.
			profile, isNew, blockingLock = nil, false, nil
			local now = os.time()

			local record, isCorrupt = decodeRecord(current)
			if isCorrupt then
				status = "Corrupt"
				return nil
			end

			local loaded: Types.PlayerData
			if record then
				if isLockBlocking(record.SessionLock, session.SessionId, serverId, now, hasLiveLocalSession) then
					status = "Locked"
					blockingLock = record.SessionLock
					return nil
				end
				if not migrateProfile(record.Profile) then
					status = "TooNew"
					return nil
				end
				loaded = record.Profile
				backfillProfile(loaded)
			else
				loaded = createDefaultProfile() -- GetAsync-equivalent succeeded and returned nil: new player
				isNew = true
			end

			status = "Acquired"
			profile = loaded
			return {
				RecordFormat = RECORD_FORMAT,
				Profile = loaded,
				SessionLock = { JobId = serverId, SessionId = session.SessionId, LockedAt = now },
			}
		end)
	end)

	if not ok then
		Logger:Warn("DATA", "DataStore read failed for player %s (%d): %s", session.Player.Name, session.UserId, tostring(err))
		return "Error", nil, false, nil
	end
	return status, profile, isNew, blockingLock
end

local function activateSession(session: Session, profile: Types.PlayerData)
	session.Profile = profile
	session.State = "Active"
	loadedProfiles[session.Player] = profile

	-- Broadcast initial profile state to client
	Network.FireClient("PlayerDataLoaded", session.Player, profile)
end

local function loadSession(session: Session)
	local player = session.Player

	if persistenceMode == "Mock" then
		activateSession(session, createDefaultProfile())
		Logger:Info("DATA", "Created in-memory (mock) profile for player %s (%d)", player.Name, session.UserId)
		return
	end
	if persistenceMode == "Unavailable" then
		Logger:Error("DATA", "DataStore unavailable: refusing to load player %s (%d)", player.Name, session.UserId)
		kickForData(session, "Saves are temporarily unavailable. Your progress is safe, please rejoin later.")
		return
	end

	-- Quick rejoin on the same server: let the previous session finish its final save first.
	waitUntil(function()
		return not hasOtherLocalSession(session)
	end, DS.SHUTDOWN_TIMEOUT_SECONDS)

	local errorCount = 0
	local lockWaitDeadline = os.clock() + DS.LOCK_WAIT_SECONDS

	while true do
		if session.Cancelled or not player.Parent or isShuttingDown then
			closeSession(session, "Failed") -- Nothing acquired yet: nothing to save or release
			return
		end

		local status, profile, isNew, blockingLock = tryAcquire(session)

		if status == "Acquired" and profile then
			if session.Cancelled or not player.Parent then
				-- Player left during the load: give the lock back right away (profile is unchanged).
				session.Profile = profile
				session.State = "Active"
				releaseSession(session)
				return
			end
			activateSession(session, profile)
			Logger:Info(
				"DATA",
				"%s profile for player %s (%d), session lock acquired",
				if isNew then "Created new" else "Loaded",
				player.Name,
				session.UserId
			)
			return
		elseif status == "Corrupt" then
			Logger:Error("DATA", "Unreadable save for player %s (%d): left untouched", player.Name, session.UserId)
			kickForData(session, "Your save could not be read. It has not been modified; please contact support.")
			return
		elseif status == "TooNew" then
			Logger:Warn("DATA", "Profile of player %s (%d) was written by a newer game version", player.Name, session.UserId)
			kickForData(session, "This server runs an older game version. Please rejoin to get the latest one.")
			return
		elseif status == "Locked" then
			local lock = blockingLock :: SessionLock
			if os.clock() >= lockWaitDeadline then
				Logger:Warn(
					"DATA",
					"Profile of player %s (%d) still locked by server %s since %d",
					player.Name,
					session.UserId,
					tostring(lock.JobId),
					lock.LockedAt
				)
				kickForData(session, "Your save is still open on another server. Please rejoin in a minute.")
				return
			end
			task.wait(DS.LOAD_RETRY_DELAY_SECONDS)
		else -- "Error": the read itself failed (outage, throttling). Never fall back to a blank profile.
			errorCount += 1
			if errorCount >= DS.LOAD_MAX_ATTEMPTS then
				Logger:Error(
					"DATA",
					"Giving up loading player %s (%d) after %d failed attempts",
					player.Name,
					session.UserId,
					errorCount
				)
				kickForData(session, "Your data could not be loaded (Roblox DataStore error). Your progress is safe, please rejoin.")
				return
			end
			task.wait(DS.LOAD_RETRY_DELAY_SECONDS * errorCount)
		end
	end
end

-- Snapshot of current sessions (the live table changes while saves yield)
local function snapshotSessions(): { Session }
	local list = {}
	for _, session in pairs(sessions) do
		table.insert(list, session)
	end
	return list
end

function PlayerDataService:Init()
	Logger:Info("DATA", "Initializing PlayerDataService...")

	if DS.LOCK_STALE_SECONDS <= 2 * Config.AUTOSAVE_INTERVAL_SECONDS then
		Logger:Warn("DATA", "LOCK_STALE_SECONDS should be well above AUTOSAVE_INTERVAL_SECONDS (autosave refreshes locks)")
	end

	if isStudio and Config.STUDIO_MOCK_DATASTORE then
		persistenceMode = "Mock"
		Logger:Info("DATA", "Studio mock DataStore active: in-memory profiles, nothing is persisted")
	else
		local success, store = pcall(function()
			return DataStoreService:GetDataStore(DS.NAME)
		end)
		if success then
			playerDataStore = store
			persistenceMode = "DataStore"
			Logger:Info("DATA", "DataStore '%s' successfully connected (server id %s)", DS.NAME, serverId)
		elseif isStudio then
			persistenceMode = "Mock"
			Logger:Warn("DATA", "Failed to connect to DataStore in Studio (API disabled?): using in-memory profiles")
		else
			persistenceMode = "Unavailable"
			Logger:Error("DATA", "Failed to connect to DataStore '%s': players cannot be loaded", DS.NAME)
		end
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
		self:_releasePlayerProfile(player)
	end)

	game:BindToClose(function()
		isShuttingDown = true
		Logger:Info("DATA", "Server closing, saving all active player profiles...")
		for _, session in ipairs(snapshotSessions()) do
			task.spawn(releaseSession, session)
		end
		local allReleased = waitUntil(function()
			return next(sessions) == nil
		end, DS.SHUTDOWN_TIMEOUT_SECONDS)
		if not allReleased then
			Logger:Error("DATA", "Shutdown timeout: some profiles were not released (their locks will go stale)")
		end
	end)

	-- Periodic autosave (also refreshes the session locks)
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_INTERVAL_SECONDS)
			Logger:Debug("DATA", "Running periodic autosave cycle...")
			for _, session in ipairs(snapshotSessions()) do
				if session.State == "Active" and not session.Saving and session.Player.Parent then
					self:_savePlayerProfile(session.Player)
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
	if sessions[player] then
		return -- Already loading/loaded (PlayerAdded and the startup loop can both fire)
	end
	local session: Session = {
		Player = player,
		UserId = player.UserId,
		Key = "User_" .. tostring(player.UserId),
		SessionId = HttpService:GenerateGUID(false),
		Profile = nil,
		State = "Loading",
		Cancelled = false,
		Saving = false,
	}
	sessions[player] = session
	loadSession(session)
end

-- Intermediate save (autosave): keeps the lock and refreshes its timestamp.
function PlayerDataService:_savePlayerProfile(player: Player)
	local session = sessions[player]
	if not session or session.State ~= "Active" or session.Saving then
		return
	end
	if not playerDataStore then
		Logger:Debug("DATA", "Mock profile updated in-memory for player %s", player.Name)
		return
	end

	local status = writeSession(session, false)
	if status == "Saved" then
		Logger:Info("DATA", "Saved profile for player %s (%d)", player.Name, player.UserId)
	elseif status == "LockLost" and session.State == "Active" then
		onLockLost(session)
	end
end

-- Final save + lock release (PlayerRemoving). Safe to call several times.
function PlayerDataService:_releasePlayerProfile(player: Player)
	local session = sessions[player]
	if session then
		releaseSession(session)
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
