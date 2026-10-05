--!strict
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local MonsterDefinitions = require(ReplicatedStorage.Shared.MonsterDefinitions)
local Network = require(ReplicatedStorage.Shared.Utility.Network)

local PlayerDataService: any = nil
local MonsterService: any = nil

local BreedingService = {}

-- Special rare mutation recipes
local MUTATION_RECIPES: { [string]: string } = {
	["emberfox+noctyra"] = "voidfox",
	["noctyra+emberfox"] = "voidfox",
}

local function inheritIVs(parentA: Types.MonsterInstance, parentB: Types.MonsterInstance): Types.MonsterIVs
	local stats = { "Health", "Attack", "Defense", "Speed" }
	local childIVs: any = {}

	for _, statName in ipairs(stats) do
		local valA = (parentA.IVs :: any)[statName] or 5
		local valB = (parentB.IVs :: any)[statName] or 5
		local avg = math.round((valA + valB) / 2)
		local variance = math.random(-Config.BREEDING.GENETIC_VARIANCE_RANGE, Config.BREEDING.GENETIC_VARIANCE_RANGE)
		local finalIV = math.clamp(avg + variance, 0, 15)

		-- 2% chance for spontaneous maximum genetic potential
		if math.random() <= 0.02 then
			finalIV = 15
		end

		childIVs[statName] = finalIV
	end

	return childIVs :: Types.MonsterIVs
end

local function determineChildSpecies(parentA: Types.MonsterInstance, parentB: Types.MonsterInstance): string
	local defA = MonsterDefinitions.Get(parentA.SpeciesId)
	local defB = MonsterDefinitions.Get(parentB.SpeciesId)
	if not defA or not defB then
		return parentA.SpeciesId
	end

	-- Check for rare mutation recipe
	local recipeKey = string.format("%s+%s", parentA.SpeciesId, parentB.SpeciesId)
	local mutationTarget = MUTATION_RECIPES[recipeKey]
	if mutationTarget and math.random() <= Config.BREEDING.BASE_MUTATION_CHANCE then
		Logger:Info("BREEDING", "Discovery! Rare mutation recipe triggered: %s", mutationTarget)
		return mutationTarget
	end

	-- 45% Parent A, 45% Parent B, 10% element-based alternative
	local roll = math.random(1, 100)
	if roll <= 45 then
		return parentA.SpeciesId
	elseif roll <= 90 then
		return parentB.SpeciesId
	else
		-- Select a species sharing at least one element with parents
		local parentElements: { [Types.ElementType]: boolean } = {}
		for _, elem in ipairs(defA.Elements) do parentElements[elem] = true end
		for _, elem in ipairs(defB.Elements) do parentElements[elem] = true end

		local compatibleCandidates: { string } = {}
		for spId, def in pairs(MonsterDefinitions.GetAll()) do
			for _, elem in ipairs(def.Elements) do
				if parentElements[elem] then
					table.insert(compatibleCandidates, spId)
					break
				end
			end
		end

		if #compatibleCandidates > 0 then
			return compatibleCandidates[math.random(1, #compatibleCandidates)]
		end
		return parentA.SpeciesId
	end
end

function BreedingService:Init()
	Logger:Info("BREEDING", "Initializing BreedingService...")
	PlayerDataService = require(script.Parent.PlayerDataService)
	MonsterService = require(script.Parent.MonsterService)

	-- Remotes
	Network.HandleFunction("StartBreeding", function(player: Player, payload: any)
		if typeof(payload) ~= "table" or typeof(payload.ParentA_UUID) ~= "string" or typeof(payload.ParentB_UUID) ~= "string" then
			return false, "Invalid breeding arguments"
		end
		return self:StartBreeding(player, payload.ParentA_UUID, payload.ParentB_UUID)
	end)

	Network.HandleFunction("ClaimBreedingEgg", function(player: Player, sessionId: any)
		if typeof(sessionId) ~= "string" then
			return false, "Invalid session ID"
		end
		return self:ClaimHatchedEgg(player, sessionId)
	end)
end

function BreedingService:Start()
	-- Ready
end

function BreedingService:StartBreeding(player: Player, parentUUID_A: string, parentUUID_B: string): (boolean, string?)
	if parentUUID_A == parentUUID_B then
		return false, "Cannot breed a monster with itself"
	end

	local profile = PlayerDataService:GetProfile(player)
	if not profile then return false, "No player profile" end

	local parentA = profile.Monsters[parentUUID_A]
	local parentB = profile.Monsters[parentUUID_B]
	if not parentA or not parentB then
		return false, "You do not own both specified monsters"
	end

	-- Check if either parent is already busy in an active breeding session
	for _, session in pairs(profile.BreedingSessions) do
		if not session.IsHatched then
			if session.ParentA_UUID == parentUUID_A or session.ParentB_UUID == parentUUID_A or
			   session.ParentA_UUID == parentUUID_B or session.ParentB_UUID == parentUUID_B then
				return false, "One of the chosen monsters is already in a breeding session"
			end
		end
	end

	-- Check elemental compatibility
	local defA = MonsterDefinitions.Get(parentA.SpeciesId)
	local defB = MonsterDefinitions.Get(parentB.SpeciesId)
	if not defA or not defB then return false, "Invalid species definition" end

	local isCompatible = false
	for _, compElem in ipairs(defA.Breeding.CompatibleElements) do
		if table.find(defB.Elements, compElem) then
			isCompatible = true
			break
		end
	end

	if not isCompatible then
		return false, "These two species are not elementally compatible for breeding"
	end

	-- Calculate breeding outcome
	local childSpecies = determineChildSpecies(parentA, parentB)
	local childIVs = inheritIVs(parentA, parentB)
	local duration = Config.BREEDING.DEFAULT_BREED_TIME_SECONDS
	local now = os.time()
	local sessionId = HttpService:GenerateGUID(false)

	local newSession: Types.BreedingSession = {
		Id = sessionId,
		ParentA_UUID = parentUUID_A,
		ParentB_UUID = parentUUID_B,
		StartedAt = now,
		DurationSeconds = duration,
		EggReadyAt = now + duration,
		EggSpeciesId = childSpecies,
		EggIVs = childIVs,
		IsCompleted = false,
		IsHatched = false,
	}

	PlayerDataService:UpdateProfile(player, function(prof)
		prof.BreedingSessions[sessionId] = newSession
	end)

	Logger:Info("BREEDING", "Player %s started breeding %s + %s -> Session %s (Ready in %ds)",
		player.Name, defA.DisplayName, defB.DisplayName, sessionId, duration)

	Network.FireClient("BreedingStarted", player, newSession)
	return true, nil
end

function BreedingService:ClaimHatchedEgg(player: Player, sessionId: string): (boolean, any)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then return false, "No player profile" end

	local session = profile.BreedingSessions[sessionId]
	if not session then
		return false, "Breeding session does not exist"
	end

	if session.IsHatched then
		return false, "Egg already claimed"
	end

	local now = os.time()
	if now < session.EggReadyAt then
		local remaining = session.EggReadyAt - now
		return false, string.format("Egg is still incubating! %d seconds remaining", remaining)
	end

	local parentA = profile.Monsters[session.ParentA_UUID]
	local parentB = profile.Monsters[session.ParentB_UUID]
	local generation = 2
	if parentA and parentB then
		generation = math.max(parentA.Generation, parentB.Generation) + 1
	end

	-- Create the child monster
	local success, newMonster = MonsterService:CreateMonster(
		player,
		session.EggSpeciesId,
		session.EggIVs,
		{ session.ParentA_UUID, session.ParentB_UUID },
		generation
	)

	if not success or not newMonster then
		return false, "Failed to hatch monster"
	end

	PlayerDataService:UpdateProfile(player, function(prof)
		local s = prof.BreedingSessions[sessionId]
		if s then
			s.IsCompleted = true
			s.IsHatched = true
		end
	end)

	Logger:Info("BREEDING", "Player %s hatched egg! New monster: %s (Gen %d, UUID: %s)",
		player.Name, newMonster.SpeciesId, generation, newMonster.UUID)

	Network.FireClient("EggHatched", player, newMonster)
	return true, newMonster
end

return BreedingService
