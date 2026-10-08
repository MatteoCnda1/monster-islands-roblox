--!strict
-- Pure starter-monster rules (no Roblox services, no side effects outside the profile passed in).
-- Used by PlayerDataService (createDefaultProfile / backfillProfile) and exercised by tests/run_tests.luau.
--
-- Every player owns the two starter monsters needed to reach the breeding loop (issue #16):
--   1. Config.STARTING_MONSTER_SPECIES ("Blaze" the Emberfox);
--   2. one species drawn from Config.SECOND_STARTER_POOL, compatible with the first one.
--
-- Must stay non-yielding: EnsureStarters runs inside an UpdateAsync transform. Randomness and UUID
-- generation are injected (`random` behaves like math.random, `newUUID` like HttpService:GenerateGUID).
local Types = require(script.Parent.Types)
local Config = require(script.Parent.Config)
local MonsterDefinitions = require(script.Parent.MonsterDefinitions)
local BreedingMath = require(script.Parent.BreedingMath)

export type RandomFn = (number?, number?) -> number
export type StarterEntry = { SpeciesId: string, Nickname: string }

local StarterMonsters = {}

-- Number of monsters a profile is topped up to (two parents are needed to breed).
StarterMonsters.STARTER_COUNT = 2

function StarterMonsters.RollIVs(random: RandomFn?): Types.MonsterIVs
	local rand: RandomFn = random or math.random
	local range = Config.STARTER_IV_RANGE
	return {
		Health = rand(range.Min, range.Max),
		Attack = rand(range.Min, range.Max),
		Defense = rand(range.Min, range.Max),
		Speed = rand(range.Min, range.Max),
	}
end

-- A fresh level-1, first-generation monster, not assigned to any plot.
function StarterMonsters.Build(
	uuid: string,
	speciesId: string,
	nickname: string?,
	ivs: Types.MonsterIVs,
	now: number
): Types.MonsterInstance
	local def = MonsterDefinitions.Get(speciesId)
	if not def then
		error(string.format("Starter species %s not found in MonsterDefinitions", tostring(speciesId)))
	end
	local calculatedStats, maxHealth = MonsterDefinitions.CalculateStats(speciesId, 1, ivs)
	return {
		UUID = uuid,
		SpeciesId = speciesId,
		Nickname = nickname,
		Level = 1,
		XP = 0,
		CurrentHealth = maxHealth,
		MaxHealth = maxHealth,
		IVs = ivs,
		CalculatedStats = calculatedStats,
		SkillsEquipped = table.clone(def.Skills),
		Parents = nil,
		Generation = 1,
		AssignedPlotId = nil,
		CreatedAt = now,
	}
end

-- True when the two species can breed whichever one is passed as parent A.
function StarterMonsters.CanBreedTogether(speciesA: string, speciesB: string): boolean
	local defA = MonsterDefinitions.Get(speciesA)
	local defB = MonsterDefinitions.Get(speciesB)
	if not defA or not defB then
		return false
	end
	return BreedingMath.AreCompatible(defA, defB) and BreedingMath.AreCompatible(defB, defA)
end

-- Pool entries that can breed with every species in `ownedSpecies` (whole pool when none fits).
function StarterMonsters.GetSecondStarterCandidates(ownedSpecies: { string }): { StarterEntry }
	local candidates: { StarterEntry } = {}
	for _, entry in ipairs(Config.SECOND_STARTER_POOL) do
		local fits = true
		for _, speciesId in ipairs(ownedSpecies) do
			if not StarterMonsters.CanBreedTogether(entry.SpeciesId, speciesId) then
				fits = false
				break
			end
		end
		if fits then
			table.insert(candidates, entry)
		end
	end
	if #candidates == 0 then
		return table.clone(Config.SECOND_STARTER_POOL)
	end
	return candidates
end

function StarterMonsters.CountMonsters(profile: Types.PlayerData): number
	local count = 0
	for _ in pairs(profile.Monsters) do
		count += 1
	end
	return count
end

-- Adds `monster` to the profile. It joins the team while the team has room (Config.MAX_TEAM_SIZE)
-- and is placed on the first unlocked plot with room (MaxMonstersCapacity); otherwise it simply
-- stays in the collection, unassigned, and the player can place it / add it to the team later.
function StarterMonsters.AddToProfile(profile: Types.PlayerData, monster: Types.MonsterInstance)
	profile.Monsters[monster.UUID] = monster

	if #profile.TeamMonsterUUIDs < Config.MAX_TEAM_SIZE and not table.find(profile.TeamMonsterUUIDs, monster.UUID) then
		table.insert(profile.TeamMonsterUUIDs, monster.UUID)
	end

	for _, plotConfig in ipairs(Config.PLOTS) do
		local plotData = profile.Plots[tostring(plotConfig.Id)]
		if plotData and plotData.IsUnlocked then
			plotData.PlacedMonsters = plotData.PlacedMonsters or {}
			if #plotData.PlacedMonsters < plotConfig.MaxMonstersCapacity then
				table.insert(plotData.PlacedMonsters, monster.UUID)
				monster.AssignedPlotId = plotConfig.Id
				break
			end
		end
	end
end

-- Tops the profile up to STARTER_COUNT monsters: adds the Emberfox starter to an empty profile,
-- then a second starter compatible with the monster already owned. Idempotent: a profile that
-- already owns two monsters or more is left untouched. Returns the monsters added (in order).
function StarterMonsters.EnsureStarters(
	profile: Types.PlayerData,
	newUUID: () -> string,
	random: RandomFn?,
	now: number
): { Types.MonsterInstance }
	local rand: RandomFn = random or math.random
	profile.Monsters = profile.Monsters or {}
	profile.TeamMonsterUUIDs = profile.TeamMonsterUUIDs or {}
	profile.Plots = profile.Plots or {}

	local added: { Types.MonsterInstance } = {}
	local count = StarterMonsters.CountMonsters(profile)

	if count == 0 then
		local first = StarterMonsters.Build(
			newUUID(),
			Config.STARTING_MONSTER_SPECIES,
			Config.STARTING_MONSTER_NICKNAME,
			StarterMonsters.RollIVs(rand),
			now
		)
		StarterMonsters.AddToProfile(profile, first)
		table.insert(added, first)
		count += 1
	end

	if count < StarterMonsters.STARTER_COUNT then
		local owned: { string } = {}
		for _, monster in pairs(profile.Monsters) do
			table.insert(owned, monster.SpeciesId)
		end
		local candidates = StarterMonsters.GetSecondStarterCandidates(owned)
		local entry = candidates[rand(1, #candidates)]
		local second = StarterMonsters.Build(newUUID(), entry.SpeciesId, entry.Nickname, StarterMonsters.RollIVs(rand), now)
		StarterMonsters.AddToProfile(profile, second)
		table.insert(added, second)
	end

	return added
end

return StarterMonsters
