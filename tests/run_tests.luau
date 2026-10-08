--!strict
--[[
	Monster Islands — unit tests against the REAL code of src/ (run outside Roblox).

	Run with `./tools/test.sh` (not `luau tests/run_tests.luau` alone: the bundle below must be generated first).

	How modules are loaded
	----------------------
	The `luau` CLI has no file I/O (`io` is absent) and its globals are read-only, so a module loaded with
	`require("./x")` can neither see a `script` global nor Roblox globals such as `Vector3`. Therefore:

	1. `tools/test.sh` writes `build/test_sources.luau`, a table of the source text of every
	   `src/**/*.luau` file, keyed by path relative to src/ without extension (`"shared/Config"`,
	   `"shared/Utility/Logger"`, `"server/Services/CombatService"`…).
	2. Every file of src/ (server and client included) is compiled with `loadstring` — without running it —
	   so a syntax error anywhere fails the suite (rojo build does not parse Luau).
	3. `loadShared(path)` below compiles a src/shared module and runs it with (via `setfenv`) an
	   environment containing:
	   - a fake `script` from a minimal Instance tree mirroring src/, so `script.Parent.Types` or
	     `script.Parent.Parent.Config` resolve to sibling modules (missing children raise an error, as in Roblox);
	   - a `require` accepting those fake instances (results cached: one load per module, as in Roblox);
	   - minimal mocks of the Roblox globals used at load time (`Vector3`, `Color3`, `Enum`, `warn`).
	4. Tests call the real functions. Changing a formula in src/shared changes what these tests see.

	Only pure modules can be loaded this way (no `game:GetService`). Logic that lives inside services must be
	extracted into a pure module under src/shared (e.g. CombatMath, BreedingMath, PlotMath, EconomyMath) and
	used by both the service and the tests.

	Mini-framework: `test(name, fn)`, `assert_eq`, `assert_near`, `assert_true`, `assert_false`, `assert_errors`.
]]

-- =====================================================================
-- Minimal Roblox global mocks (only what src/shared touches at load time)
-- =====================================================================
local Color3Mock = {
	fromRGB = function(r: number, g: number, b: number)
		return { R = r / 255, G = g / 255, B = b / 255 }
	end,
	new = function(r: number, g: number, b: number)
		return { R = r, G = g, B = b }
	end,
}

local Vector3Mock = {
	new = function(x: number?, y: number?, z: number?)
		return { X = x or 0, Y = y or 0, Z = z or 0 }
	end,
}

-- Enum.<Category>.<Item> resolves to the string "Enum.<Category>.<Item>"
local EnumMock = setmetatable({}, {
	__index = function(_, category: string)
		return setmetatable({}, {
			__index = function(_, item: string)
				return "Enum." .. category .. "." .. item
			end,
		})
	end,
})

local function warnMock(...: any)
	print("[warn]", ...)
end

-- =====================================================================
-- Loader for src/shared modules (see header)
-- =====================================================================
local bundleOk, Sources = pcall(require, "../build/test_sources")
if not bundleOk then
	error("Cannot load build/test_sources.luau — run the tests with ./tools/test.sh (it generates the bundle). " .. tostring(Sources), 0)
end

local moduleCache: { [string]: any } = {}
local loadModuleNode: (node: any) -> any

local function newFakeInstance(name: string, parent: any, path: string?): any
	local node = { Name = name, Parent = parent, _path = path, _children = {} }
	return setmetatable(node, {
		__index = function(self: any, key: string)
			if key == "Parent" then
				return nil -- root of the fake tree
			end
			local child = rawget(self, "_children")[key]
			if child == nil then
				error(string.format("%s is not a valid member of %s", tostring(key), rawget(self, "Name")), 2)
			end
			return child
		end,
		__tostring = function(self: any)
			return rawget(self, "Name")
		end,
	})
end

local srcRoot = newFakeInstance("src", nil, nil)

for path in pairs(Sources) do
	local parts = string.split(path, "/")
	local dir = srcRoot
	for i = 1, #parts - 1 do
		local children = rawget(dir, "_children")
		if not children[parts[i]] then
			children[parts[i]] = newFakeInstance(parts[i], dir, nil)
		end
		dir = children[parts[i]]
	end
	rawget(dir, "_children")[parts[#parts]] = newFakeInstance(parts[#parts], dir, path)
end

local sharedRoot = srcRoot.shared
local baseEnv = getfenv(1)

loadModuleNode = function(node: any): any
	local path = rawget(node, "_path")
	if path == nil then
		error(string.format("require: %s is not a ModuleScript", tostring(node)), 2)
	end
	if moduleCache[path] ~= nil then
		return moduleCache[path]
	end

	local chunk, compileErr = loadstring(Sources[path], "=src/" .. path .. ".luau")
	if not chunk then
		error(compileErr, 0)
	end

	local env = setmetatable({
		script = node,
		require = loadModuleNode,
		Vector3 = Vector3Mock,
		Color3 = Color3Mock,
		Enum = EnumMock,
		warn = warnMock,
	}, { __index = baseEnv })
	setfenv(chunk, env)

	local result = chunk()
	moduleCache[path] = result
	return result
end

-- Loads src/shared/<path>.luau, e.g. loadShared("Config") or loadShared("Utility/Logger").
local function loadShared(path: string): any
	local parts = string.split(path, "/")
	local node = sharedRoot
	for _, part in ipairs(parts) do
		node = node[part]
	end
	return loadModuleNode(node)
end

-- Scripted RNG: each call returns the next value (whatever the arguments) and records the arguments.
local function scriptedRandom(values: { number }): ((number?, number?) -> number, { { any } })
	local index = 0
	local calls: { { any } } = {}
	local function rand(m: number?, n: number?): number
		index += 1
		table.insert(calls, { m, n })
		local v = values[index]
		if v == nil then
			error(string.format("scriptedRandom exhausted after %d values", #values), 2)
		end
		return v
	end
	return rand, calls
end

-- =====================================================================
-- Mini test framework
-- =====================================================================
local totalTests = 0
local passedTests = 0
local failedTests = 0

local function test(name: string, fn: () -> ())
	totalTests += 1
	local ok, err = pcall(fn)
	if ok then
		passedTests += 1
		print(string.format("  ✓ %s", name))
	else
		failedTests += 1
		print(string.format("  ✗ %s: %s", name, tostring(err)))
	end
end

local function assert_eq(actual: any, expected: any, msg: string?)
	if actual ~= expected then
		error(string.format("Assertion failed: expected %s, got %s. %s", tostring(expected), tostring(actual), msg or ""), 2)
	end
end

local function assert_near(actual: number, expected: number, msg: string?)
	if math.abs(actual - expected) > 1e-9 then
		error(string.format("Assertion failed: expected ~%s, got %s. %s", tostring(expected), tostring(actual), msg or ""), 2)
	end
end

local function assert_true(cond: any, msg: string?)
	if not cond then
		error(string.format("Assertion failed: expected true, got %s. %s", tostring(cond), msg or ""), 2)
	end
end

local function assert_false(cond: any, msg: string?)
	if cond then
		error(string.format("Assertion failed: expected false, got %s. %s", tostring(cond), msg or ""), 2)
	end
end

local function assert_errors(fn: () -> (), msg: string?)
	local ok = pcall(fn)
	if ok then
		error(string.format("Assertion failed: expected an error. %s", msg or ""), 2)
	end
end

-- =====================================================================
-- Modules under test (real src/shared code)
-- =====================================================================
local Config = loadShared("Config")
local ElementDefinitions = loadShared("ElementDefinitions")
local MonsterDefinitions = loadShared("MonsterDefinitions")
local AttackDefinitions = loadShared("AttackDefinitions")
local CombatMath = loadShared("CombatMath")
local BreedingMath = loadShared("BreedingMath")
local PlotMath = loadShared("PlotMath")
local EconomyMath = loadShared("EconomyMath")

local ALL_ELEMENTS = { "Fire", "Water", "Earth", "Wind", "Nature", "Shadow", "Light", "Arcane" }
local ZERO_IVS = { Health = 0, Attack = 0, Defense = 0, Speed = 0 }

print("========================================")
print(" Running Monster Islands Unit Tests")
print("========================================")

-- 0. LOADER & SYNTAX
print("\n[Suite: Loader & Syntax]")
test("Every src/ file compiles (syntax check, server and client included)", function()
	local paths = {}
	for path in pairs(Sources) do
		table.insert(paths, path)
	end
	table.sort(paths)
	assert_true(#paths > 0, "empty bundle")
	local errors = {}
	for _, path in ipairs(paths) do
		local chunk, err = loadstring(Sources[path], "=src/" .. path .. ".luau")
		if not chunk then
			table.insert(errors, tostring(err))
		end
	end
	assert_eq(#errors, 0, table.concat(errors, " | "))
end)

test("Modules are cached and nested script.Parent.Parent requires resolve", function()
	assert_true(loadShared("Config") == Config, "Second load must return the cached module")
	local Logger = loadShared("Utility/Logger") -- requires script.Parent.Parent.Config
	assert_eq(typeof(Logger.SetLogLevel), "function")
end)

test("Missing sibling module raises an error like Roblox", function()
	assert_errors(function()
		loadShared("DoesNotExist")
	end)
end)

-- 1. ECONOMY
print("\n[Suite: Economy]")
test("EconomyMath.IsValidAmount accepts finite positive numbers", function()
	assert_true(EconomyMath.IsValidAmount(100))
	assert_true(EconomyMath.IsValidAmount(0.5))
end)

test("EconomyMath.IsValidAmount rejects zero, negatives, NaN, infinities and non-numbers", function()
	assert_false(EconomyMath.IsValidAmount(0))
	assert_false(EconomyMath.IsValidAmount(-50))
	assert_false(EconomyMath.IsValidAmount(0 / 0))
	assert_false(EconomyMath.IsValidAmount(math.huge))
	assert_false(EconomyMath.IsValidAmount(-math.huge))
	assert_false(EconomyMath.IsValidAmount("100"))
	assert_false(EconomyMath.IsValidAmount(nil))
end)

-- 2. ELEMENTS
print("\n[Suite: Elements]")
test("Fire deals 1.5x super effective damage against Nature", function()
	assert_eq(ElementDefinitions.GetEffectiveness("Fire", "Nature"), 1.5)
end)

test("Water deals 0.75x reduced damage against Nature", function()
	assert_eq(ElementDefinitions.GetEffectiveness("Water", "Nature"), 0.75)
end)

test("Unlisted matchups and unknown elements are neutral (1.0)", function()
	assert_eq(ElementDefinitions.GetEffectiveness("Fire", "Earth"), 1.0)
	assert_eq(ElementDefinitions.GetEffectiveness("Arcane", "Shadow"), 1.0)
	assert_eq(ElementDefinitions.GetEffectiveness("Plasma", "Fire"), 1.0)
end)

test("Arcane is slightly effective against the four natural elements", function()
	for _, elem in ipairs({ "Fire", "Water", "Nature", "Earth" }) do
		assert_eq(ElementDefinitions.GetEffectiveness("Arcane", elem), 1.2, elem)
	end
end)

test("Every element matchup multiplier stays within [0.5, 2]", function()
	for _, atk in ipairs(ALL_ELEMENTS) do
		for _, def in ipairs(ALL_ELEMENTS) do
			local m = ElementDefinitions.GetEffectiveness(atk, def)
			assert_true(m >= 0.5 and m <= 2, atk .. " vs " .. def)
		end
	end
end)

test("Every element has a color, unknown elements get the grey fallback", function()
	for _, elem in ipairs(ALL_ELEMENTS) do
		assert_true(ElementDefinitions.GetElementColor(elem) ~= nil, elem)
	end
	local fallback = ElementDefinitions.GetElementColor("Plasma")
	assert_near(fallback.R, 200 / 255)
end)

-- 3. MONSTER & ATTACK DEFINITIONS
print("\n[Suite: Monster & Attack Definitions]")
test("CalculateStats at level 1 with zero IVs returns base stats and doubled health", function()
	local stats, maxHealth = MonsterDefinitions.CalculateStats("emberfox", 1, ZERO_IVS)
	assert_eq(stats.Attack, 28)
	assert_eq(stats.Defense, 14)
	assert_eq(stats.Speed, 24)
	assert_eq(maxHealth, 190)
	assert_eq(stats.Health, maxHealth)
end)

test("CalculateStats applies level growth and IVs (health IVs weigh x3)", function()
	-- emberfox Lv10: Attack floor(28 + 4.2*9 + 3) = 68, Defense floor(14 + 2.2*9 + 2) = 35,
	-- Speed floor(24 + 3.5*9 + 1) = 56, Health floor(95*2 + 9*9*1.5 + 5*3) = 326
	local stats, maxHealth = MonsterDefinitions.CalculateStats("emberfox", 10, { Health = 5, Attack = 3, Defense = 2, Speed = 1 })
	assert_eq(stats.Attack, 68)
	assert_eq(stats.Defense, 35)
	assert_eq(stats.Speed, 56)
	assert_eq(maxHealth, 326)
end)

test("CalculateStats raises an error for an unknown species", function()
	assert_errors(function()
		MonsterDefinitions.CalculateStats("missingno", 1, ZERO_IVS)
	end)
end)

test("Every species is consistent: Id matches key, elements set, skills exist", function()
	for id, def in pairs(MonsterDefinitions.GetAll()) do
		assert_eq(def.Id, id)
		assert_true(#def.Elements > 0, id .. " has no element")
		assert_true(#def.Breeding.CompatibleElements > 0, id .. " has no compatible element")
		for _, skillId in ipairs(def.Skills) do
			assert_true(AttackDefinitions.Get(skillId) ~= nil, id .. " references unknown skill " .. skillId)
		end
	end
end)

test("Every attack is consistent: Id matches key, accuracy in 1..100, support moves deal no damage", function()
	for id, atk in pairs(AttackDefinitions.GetAll()) do
		assert_eq(atk.Id, id)
		assert_true(atk.Accuracy >= 1 and atk.Accuracy <= 100, id .. " accuracy")
		assert_true(table.find(ALL_ELEMENTS, atk.Element) ~= nil, id .. " element")
		if atk.EffectType == "Shield" or atk.EffectType == "SpeedBoost" then
			assert_eq(atk.Power, 0, id)
			assert_true(atk.EffectDuration ~= nil, id .. " needs an EffectDuration")
		else
			assert_true(atk.Power > 0, id .. " should deal damage")
		end
	end
end)

-- 4. COMBAT
print("\n[Suite: Combat]")
test("Base damage follows the level/power/attack/defense formula", function()
	-- ((2*1/5 + 2) * 45 * (28/14) / 50) + 2 = 6.32
	assert_near(CombatMath.ComputeBaseDamage(1, 45, 28, 14), 6.32)
end)

test("Base damage treats defense below 1 as 1", function()
	assert_near(CombatMath.ComputeBaseDamage(1, 50, 10, 0), CombatMath.ComputeBaseDamage(1, 50, 10, 1))
end)

test("Final damage applies elemental multiplier and critical boost", function()
	assert_eq(Config.COMBAT.CRIT_DAMAGE_MULTIPLIER, 1.5)
	assert_eq(CombatMath.ComputeFinalDamage(20, 1.5, true, 1.0, false), 45, "20 * 1.5 * 1.5")
	assert_eq(CombatMath.ComputeFinalDamage(20, 1.5, false, 1.0, false), 30, "20 * 1.5")
end)

test("Shield cuts incoming damage by 40% (after flooring)", function()
	assert_eq(CombatMath.ComputeFinalDamage(50, 1.0, false, 1.0, true), 30)
	assert_eq(CombatMath.ComputeFinalDamage(10.9, 1.0, false, 1.0, true), 6, "floor(floor(10.9) * 0.6)")
end)

test("Final damage is never below 1", function()
	assert_eq(CombatMath.ComputeFinalDamage(0.1, 0.75, false, 0.92, true), 1)
end)

test("Real matchup: Lv1 Emberfox FlameBurst vs Lv1 Mossaur", function()
	local emberStats = MonsterDefinitions.CalculateStats("emberfox", 1, ZERO_IVS)
	local mossStats = MonsterDefinitions.CalculateStats("mossaur", 1, ZERO_IVS)
	local flameBurst = AttackDefinitions.Get("FlameBurst")
	local mossaur = MonsterDefinitions.Get("mossaur")
	local elemMult = ElementDefinitions.GetEffectiveness(flameBurst.Element, mossaur.Elements[1])
	assert_eq(elemMult, 1.5)
	local base = CombatMath.ComputeBaseDamage(1, flameBurst.Power, emberStats.Attack, mossStats.Defense)
	-- ((0.4 + 2) * 45 * (28/26) / 50) + 2 ≈ 4.326 → * 1.5 ≈ 6.49 → 6
	assert_eq(CombatMath.ComputeFinalDamage(base, elemMult, false, 1.0, false), 6)
end)

test("Critical roll succeeds up to BASE_CRIT_CHANCE inclusive", function()
	local chance = Config.COMBAT.BASE_CRIT_CHANCE
	assert_true(CombatMath.RollIsCritical(function() return chance end))
	assert_false(CombatMath.RollIsCritical(function() return chance + 0.01 end))
end)

test("Damage variance spans [MIN_DAMAGE_VARIANCE, MAX_DAMAGE_VARIANCE]", function()
	assert_near(CombatMath.RollVariance(function() return 0 end), Config.COMBAT.MIN_DAMAGE_VARIANCE)
	assert_near(CombatMath.RollVariance(function() return 1 end), Config.COMBAT.MAX_DAMAGE_VARIANCE)
	assert_true(Config.COMBAT.MIN_DAMAGE_VARIANCE <= 1 and Config.COMBAT.MAX_DAMAGE_VARIANCE >= 1)
end)

test("Action order: priority beats speed, speed boost multiplies speed by 1.3", function()
	assert_true(CombatMath.GetActionOrderScore(1, 10, false) > CombatMath.GetActionOrderScore(0, 999, false))
	assert_eq(CombatMath.GetActionOrderScore(0, 24, false), 24)
	assert_eq(CombatMath.GetActionOrderScore(0, 24, true), 31, "floor(24 * 1.3)")
	-- A slow Mossaur using QuickStrike (priority 1) acts before a fast Zephlyn using GaleSlash
	local mossSpeed = MonsterDefinitions.CalculateStats("mossaur", 1, ZERO_IVS).Speed
	local zephSpeed = MonsterDefinitions.CalculateStats("zephlyn", 1, ZERO_IVS).Speed
	assert_true(mossSpeed < zephSpeed)
	local quick = CombatMath.GetActionOrderScore(AttackDefinitions.Get("QuickStrike").Priority, mossSpeed, false)
	local gale = CombatMath.GetActionOrderScore(AttackDefinitions.Get("GaleSlash").Priority, zephSpeed, false)
	assert_true(quick > gale)
end)

test("Burn deals 6% of max health, at least 2", function()
	assert_eq(CombatMath.ComputeBurnDamage(190), 11)
	assert_eq(CombatMath.ComputeBurnDamage(20), 2)
end)

test("Health is clamped to [0, MaxHealth] when damage is applied (KO at 0)", function()
	assert_eq(CombatMath.ApplyDamage(25, 30, 100), 0)
	assert_eq(CombatMath.ApplyDamage(50, 10, 100), 40)
	assert_eq(CombatMath.ApplyDamage(90, -50, 100), 100)
end)

-- 5. BREEDING & GENETICS
print("\n[Suite: Breeding & Genetics]")
test("IV inheritance averages parents, adds variance and clamps to 0..15", function()
	local range = Config.BREEDING.GENETIC_VARIANCE_RANGE
	-- Per stat (Health, Attack, Defense, Speed): one variance roll, then one perfect-IV roll
	local rand, calls = scriptedRandom({ 1, 0.5, -2, 0.5, -2, 0.5, 2, 0.5 })
	local child = BreedingMath.InheritIVs(
		{ Health = 10, Attack = 14, Defense = 0, Speed = 15 },
		{ Health = 14, Attack = 10, Defense = 0, Speed = 15 },
		rand
	)
	assert_eq(child.Health, 13, "avg 12 + 1")
	assert_eq(child.Attack, 10, "avg 12 - 2")
	assert_eq(child.Defense, 0, "clamped at 0")
	assert_eq(child.Speed, 15, "clamped at 15")
	assert_eq(calls[1][1], -range)
	assert_eq(calls[1][2], range)
end)

test("IV inheritance can roll a spontaneous perfect IV", function()
	local rand = scriptedRandom({ 0, 0.01, 0, 0.5, 0, 0.5, 0, 0.5 })
	local child = BreedingMath.InheritIVs(ZERO_IVS, ZERO_IVS, rand)
	assert_eq(child.Health, 15)
	assert_eq(child.Attack, 0)
end)

test("IV inheritance with math.random always stays within legal bounds", function()
	local range = Config.BREEDING.GENETIC_VARIANCE_RANGE
	for _ = 1, 300 do
		local child = BreedingMath.InheritIVs({ Health = 1, Attack = 14, Defense = 7, Speed = 0 }, { Health = 0, Attack = 15, Defense = 8, Speed = 1 })
		for stat, avg in pairs({ Health = 1, Attack = 15, Defense = 8, Speed = 1 }) do
			local v = child[stat]
			assert_true(v >= 0 and v <= 15, stat)
			assert_true(v == 15 or math.abs(v - avg) <= range, stat .. " outside variance range")
		end
	end
end)

test("Breeding compatibility follows CompatibleElements of parent A", function()
	local get = MonsterDefinitions.Get
	assert_true(BreedingMath.AreCompatible(get("emberfox"), get("noctyra")), "Fire accepts Shadow")
	assert_false(BreedingMath.AreCompatible(get("aquaphin"), get("noctyra")), "Water does not accept Shadow")
	for id, def in pairs(MonsterDefinitions.GetAll()) do
		assert_true(BreedingMath.AreCompatible(def, def), id .. " should breed with its own kind")
	end
end)

test("Rare mutation: emberfox + noctyra can give voidfox, in both orders", function()
	assert_eq(BreedingMath.GetMutationTarget("emberfox", "noctyra"), "voidfox")
	assert_eq(BreedingMath.GetMutationTarget("noctyra", "emberfox"), "voidfox")
	assert_eq(BreedingMath.GetMutationTarget("emberfox", "mossaur"), nil)
	for recipe, target in pairs(BreedingMath.MUTATION_RECIPES) do
		assert_true(MonsterDefinitions.Get(target) ~= nil, recipe .. " targets unknown species")
	end

	local species, isMutation = BreedingMath.DetermineChildSpecies("emberfox", "noctyra", scriptedRandom({ Config.BREEDING.BASE_MUTATION_CHANCE }))
	assert_eq(species, "voidfox")
	assert_true(isMutation)
end)

test("Child species: 45% parent A, 45% parent B, else a species sharing an element", function()
	local chance = Config.BREEDING.BASE_MUTATION_CHANCE
	-- Recipe pair: a failed mutation roll comes first
	assert_eq(BreedingMath.DetermineChildSpecies("emberfox", "noctyra", scriptedRandom({ chance + 0.01, 45 })), "emberfox")
	assert_eq(BreedingMath.DetermineChildSpecies("emberfox", "noctyra", scriptedRandom({ chance + 0.01, 46 })), "noctyra")
	assert_eq(BreedingMath.DetermineChildSpecies("emberfox", "noctyra", scriptedRandom({ chance + 0.01, 90 })), "noctyra")

	-- Non-recipe pair: no mutation roll; candidates sorted = { aquaphin, mossaur }
	local rand, calls = scriptedRandom({ 91, 1 })
	local species, isMutation = BreedingMath.DetermineChildSpecies("mossaur", "aquaphin", rand)
	assert_eq(species, "aquaphin")
	assert_false(isMutation)
	assert_eq(calls[1][1], 1)
	assert_eq(calls[1][2], 100)
	assert_eq(calls[2][2], 2, "picks among 2 element-sharing species")
end)

test("Element-based candidates share at least one element with a parent", function()
	local defA = MonsterDefinitions.Get("emberfox")
	local defB = MonsterDefinitions.Get("noctyra")
	local candidates = BreedingMath.GetElementCandidates(defA, defB)
	assert_eq(table.concat(candidates, ","), "emberfox,noctyra,voidfox")
end)

test("Unknown parent species falls back to parent A", function()
	local species, isMutation = BreedingMath.DetermineChildSpecies("missingno", "emberfox", scriptedRandom({}))
	assert_eq(species, "missingno")
	assert_false(isMutation)
end)

-- 6. PLOTS & DECORATIONS
print("\n[Suite: Plots & Decorations]")
test("Decoration grid snapping aligns coordinates to Config.PLOT_GRID_SIZE (4 studs)", function()
	assert_eq(Config.PLOT_GRID_SIZE, 4)
	local size = Config.PLOTS[1].Size
	local x, z = PlotMath.SnapDecorationPosition(7, -9, size)
	assert_eq(x, 8, "7 snapped to 4-stud grid should be 8")
	assert_eq(z, -8, "-9 snapped to 4-stud grid should be -8")
end)

test("Decoration placement is clamped inside the plot minus the edge margin", function()
	local size = Config.PLOTS[1].Size -- 36 x 36 → max |offset| = 18 - 2 = 16
	local x, z = PlotMath.SnapDecorationPosition(100, -100, size)
	assert_eq(x, 16)
	assert_eq(z, -16)
end)

test("Decoration snapping honours an explicit grid size", function()
	local x, z = PlotMath.SnapDecorationPosition(7, -7, { X = 36, Z = 36 }, 5)
	assert_eq(x, 5)
	assert_eq(z, -5)
end)

-- 7. CONFIG
print("\n[Suite: Config]")
test("Starting profile values reference valid data", function()
	assert_true(MonsterDefinitions.Get(Config.STARTING_MONSTER_SPECIES) ~= nil, "starter species must exist")
	assert_true(Config.STARTING_CURRENCY.Coins >= 0 and Config.STARTING_CURRENCY.Gems >= 0)
	assert_eq(Config.STARTING_PROGRESSION.Level, 1)
	assert_true(Config.MAX_TEAM_SIZE >= 1)
	assert_true(Config.DATA_VERSION >= 1 and Config.DATA_VERSION == math.floor(Config.DATA_VERSION))
end)

test("Plots: sequential ids, first plot free at level 1, costs and levels non-decreasing", function()
	assert_eq(Config.PLOTS[1].CostCoins, 0)
	assert_eq(Config.PLOTS[1].CostGems, 0)
	assert_eq(Config.PLOTS[1].RequiredLevel, 1)
	for i, plot in ipairs(Config.PLOTS) do
		assert_eq(plot.Id, i)
		assert_true(plot.MaxMonstersCapacity >= 1)
		if i > 1 then
			local prev = Config.PLOTS[i - 1]
			assert_true(plot.CostCoins >= prev.CostCoins, "plot " .. i .. " cost")
			assert_true(plot.RequiredLevel >= prev.RequiredLevel, "plot " .. i .. " level")
		end
	end
end)

test("Decorations have unique ids and a positive cost", function()
	local seen = {}
	for _, deco in ipairs(Config.DECORATIONS) do
		assert_true(not seen[deco.Id], "duplicate decoration " .. deco.Id)
		seen[deco.Id] = true
		assert_true(deco.CostCoins > 0, deco.Id)
	end
end)

test("Combat config is coherent (chances and rewards)", function()
	assert_true(Config.COMBAT.BASE_CRIT_CHANCE >= 0 and Config.COMBAT.BASE_CRIT_CHANCE <= 1)
	assert_true(Config.COMBAT.VICTORY_REWARDS.Coins > Config.COMBAT.DEFEAT_REWARDS.Coins)
	assert_true(Config.BREEDING.BASE_MUTATION_CHANCE > 0 and Config.BREEDING.BASE_MUTATION_CHANCE < 1)
end)

print("\n========================================")
print(string.format(" Test Results: %d Passed, %d Failed (Total: %d)", passedTests, failedTests, totalTests))
print("========================================")

if failedTests > 0 then
	error("Some unit tests failed!", 1)
end
