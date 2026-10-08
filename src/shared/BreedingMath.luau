--!strict
-- Pure breeding / genetics rules (no Roblox services, no side effects).
-- Used by BreedingService and exercised directly by tests/run_tests.luau.
-- Randomness is injected: `random` behaves like math.random (random() -> [0,1), random(m, n) -> integer in [m, n]).
local Types = require(script.Parent.Types)
local Config = require(script.Parent.Config)
local MonsterDefinitions = require(script.Parent.MonsterDefinitions)

export type RandomFn = (number?, number?) -> number

local BreedingMath = {}

BreedingMath.MIN_IV = 0
BreedingMath.MAX_IV = 15
BreedingMath.DEFAULT_PARENT_IV = 5 -- Used when a parent is missing an IV entry
BreedingMath.PERFECT_IV_CHANCE = 0.02 -- Spontaneous maximum genetic potential, per stat
BreedingMath.PARENT_A_WEIGHT = 45 -- Out of 100: 45% parent A, 45% parent B, 10% element-based alternative
BreedingMath.PARENT_B_WEIGHT = 45

local IV_STATS = { "Health", "Attack", "Defense", "Speed" }

-- Special rare mutation recipes ("speciesA+speciesB" -> mutated species)
BreedingMath.MUTATION_RECIPES = {
	["emberfox+noctyra"] = "voidfox",
	["noctyra+emberfox"] = "voidfox",
} :: { [string]: string }

-- Parents are compatible when A accepts at least one of B's elements.
function BreedingMath.AreCompatible(defA: Types.MonsterDefinition, defB: Types.MonsterDefinition): boolean
	for _, compElem in ipairs(defA.Breeding.CompatibleElements) do
		if table.find(defB.Elements, compElem) then
			return true
		end
	end
	return false
end

-- Each IV = rounded parent average + variance (±GENETIC_VARIANCE_RANGE), clamped to [MIN_IV, MAX_IV],
-- with a small chance to roll a perfect IV.
function BreedingMath.InheritIVs(ivsA: Types.MonsterIVs, ivsB: Types.MonsterIVs, random: RandomFn?): Types.MonsterIVs
	local rand: RandomFn = random or math.random
	local range = Config.BREEDING.GENETIC_VARIANCE_RANGE
	local childIVs: any = {}

	for _, statName in ipairs(IV_STATS) do
		local valA = (ivsA :: any)[statName] or BreedingMath.DEFAULT_PARENT_IV
		local valB = (ivsB :: any)[statName] or BreedingMath.DEFAULT_PARENT_IV
		local avg = math.round((valA + valB) / 2)
		local variance = rand(-range, range)
		local finalIV = math.clamp(avg + variance, BreedingMath.MIN_IV, BreedingMath.MAX_IV)

		if rand() <= BreedingMath.PERFECT_IV_CHANCE then
			finalIV = BreedingMath.MAX_IV
		end

		childIVs[statName] = finalIV
	end

	return childIVs :: Types.MonsterIVs
end

function BreedingMath.GetMutationTarget(speciesA: string, speciesB: string): string?
	return BreedingMath.MUTATION_RECIPES[string.format("%s+%s", speciesA, speciesB)]
end

-- Species sharing at least one element with either parent, sorted for deterministic picks.
function BreedingMath.GetElementCandidates(defA: Types.MonsterDefinition, defB: Types.MonsterDefinition): { string }
	local parentElements: { [Types.ElementType]: boolean } = {}
	for _, elem in ipairs(defA.Elements) do parentElements[elem] = true end
	for _, elem in ipairs(defB.Elements) do parentElements[elem] = true end

	local candidates: { string } = {}
	for spId, def in pairs(MonsterDefinitions.GetAll()) do
		for _, elem in ipairs(def.Elements) do
			if parentElements[elem] then
				table.insert(candidates, spId)
				break
			end
		end
	end
	table.sort(candidates)
	return candidates
end

-- Returns the child species and whether it came from a rare mutation recipe.
function BreedingMath.DetermineChildSpecies(speciesA: string, speciesB: string, random: RandomFn?): (string, boolean)
	local rand: RandomFn = random or math.random
	local defA = MonsterDefinitions.Get(speciesA)
	local defB = MonsterDefinitions.Get(speciesB)
	if not defA or not defB then
		return speciesA, false
	end

	local mutationTarget = BreedingMath.GetMutationTarget(speciesA, speciesB)
	if mutationTarget and rand() <= Config.BREEDING.BASE_MUTATION_CHANCE then
		return mutationTarget, true
	end

	local roll = rand(1, 100)
	if roll <= BreedingMath.PARENT_A_WEIGHT then
		return speciesA, false
	elseif roll <= BreedingMath.PARENT_A_WEIGHT + BreedingMath.PARENT_B_WEIGHT then
		return speciesB, false
	end

	local candidates = BreedingMath.GetElementCandidates(defA, defB)
	if #candidates > 0 then
		return candidates[rand(1, #candidates)], false
	end
	return speciesA, false
end

return BreedingMath
