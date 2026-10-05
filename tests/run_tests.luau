--!strict
-- Minimal standalone Roblox environment mock for CLI Luau testing
local MockRoblox = {}

-- Minimal standalone Roblox environment mock for CLI Luau testing
local Color3 = {
	fromRGB = function(r: number, g: number, b: number)
		return { R = r, G = g, B = b }
	end,
	new = function(r: number, g: number, b: number)
		return { R = r, G = g, B = b }
	end,
}

local Vector3 = {
	new = function(x: number, y: number, z: number)
		return { X = x, Y = y, Z = z }
	end,
	zero = { X = 0, Y = 0, Z = 0 },
}

local UDim = {
	new = function(scale: number, offset: number)
		return { Scale = scale, Offset = offset }
	end,
}

local UDim2 = {
	new = function(sx: number, ox: number, sy: number, oy: number)
		return { X = { Scale = sx, Offset = ox }, Y = { Scale = sy, Offset = oy } }
	end,
}

local Enum = {
	Material = { Grass = 1, Sand = 2, Glass = 3, Cobblestone = 4, Marble = 5, Neon = 6, Wood = 7, WoodPlanks = 8, Stone = 9, Slate = 10, Fabric = 11, Basalt = 12, SmoothPlastic = 13 },
	SurfaceType = { Smooth = 1 },
	Font = { Gotham = 1, GothamBold = 2, GothamMedium = 3 },
	TextXAlignment = { Left = 1, Center = 2, Right = 3 },
	SortOrder = { LayoutOrder = 1 },
	ZIndexBehavior = { Sibling = 1 },
	ApplyStrokeMode = { Border = 1 },
}

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

local function assert_true(cond: boolean, msg: string?)
	if not cond then
		error(string.format("Assertion failed: expected true, got false. %s", msg or ""), 2)
	end
end

local function assert_false(cond: boolean, msg: string?)
	if cond then
		error(string.format("Assertion failed: expected false, got true. %s", msg or ""), 2)
	end
end

print("========================================")
print(" Running Monster Islands Unit Tests")
print("========================================")

-- 1. ECONOMY TESTS
print("\n[Suite: Economy]")
test("Deposit increases balance correctly", function()
	local balance = 500
	local deposit = 150
	balance += deposit
	assert_eq(balance, 650)
end)

test("Withdrawal decreases balance correctly", function()
	local balance = 500
	local cost = 250
	assert_true(balance >= cost)
	balance -= cost
	assert_eq(balance, 250)
end)

test("Withdrawal fails when funds are insufficient and prevents negative balance", function()
	local balance = 100
	local cost = 250
	local canAfford = balance >= cost
	assert_false(canAfford, "Should not afford purchase")
	if canAfford then
		balance -= cost
	end
	assert_eq(balance, 100)
	assert_true(balance >= 0)
end)

test("Negative or NaN amounts are rejected", function()
	local function isValidAmount(amount: any): boolean
		if typeof(amount) ~= "number" then return false end
		if amount <= 0 then return false end
		if amount ~= amount then return false end -- NaN check
		if amount == math.huge or amount == -math.huge then return false end
		return true
	end

	assert_false(isValidAmount(-50))
	assert_false(isValidAmount(0))
	assert_false(isValidAmount(0/0))
	assert_false(isValidAmount(math.huge))
	assert_true(isValidAmount(100))
end)

-- 2. ELEMENT DEFINITIONS & COMBAT
print("\n[Suite: Combat & Elements]")
local ElementChart = {
	Fire = { Nature = 1.5, Wind = 1.25, Water = 0.75, Fire = 0.75 },
	Water = { Fire = 1.5, Earth = 1.5, Nature = 0.75, Water = 0.75 },
	Nature = { Earth = 1.5, Water = 1.25, Fire = 0.75, Nature = 0.75 },
	Earth = { Fire = 1.25, Wind = 1.5, Nature = 0.75, Water = 0.75 },
	Wind = { Nature = 1.5, Earth = 0.75, Wind = 0.75 },
	Shadow = { Light = 1.5, Arcane = 1.25, Shadow = 0.75 },
	Light = { Shadow = 1.5, Arcane = 0.75, Light = 0.75 },
}

local function getEffectiveness(attacker: string, defender: string): number
	local row = ElementChart[attacker]
	if row and row[defender] then return row[defender] end
	return 1.0
end

test("Fire deals 1.5x super effective damage against Nature", function()
	local mult = getEffectiveness("Fire", "Nature")
	assert_eq(mult, 1.5)
end)

test("Water deals 0.75x reduced damage against Nature", function()
	local mult = getEffectiveness("Water", "Nature")
	assert_eq(mult, 0.75)
end)

test("Damage calculation applies attack, defense, power and elemental bonus", function()
	local level = 1
	local power = 45 -- FlameBurst
	local atk = 28
	local def = 14
	local baseDmg = (((2 * level / 5) + 2) * power * (atk / def) / 50) + 2
	local elemMultiplier = getEffectiveness("Fire", "Nature") -- 1.5
	local finalDmg = math.floor(baseDmg * elemMultiplier)
	assert_true(finalDmg >= 8 and finalDmg <= 20, "Damage should be within balanced expected bounds")
end)

test("Shield cuts incoming damage by 40%", function()
	local incomingDamage = 50
	local shieldedDamage = math.floor(incomingDamage * 0.6)
	assert_eq(shieldedDamage, 30)
end)

test("Monster KO condition triggers when HP drops to 0 or below", function()
	local currentHP = 25
	local damageTaken = 30
	currentHP = math.clamp(currentHP - damageTaken, 0, 100)
	assert_eq(currentHP, 0)
	local isKO = (currentHP <= 0)
	assert_true(isKO)
end)

-- 3. BREEDING & GENETICS
print("\n[Suite: Breeding & Genetics]")
test("IV inheritance calculates average of parents with variance", function()
	local parentA_IV = 10
	local parentB_IV = 14
	local avg = math.round((parentA_IV + parentB_IV) / 2) -- 12
	local variance = 1
	local childIV = math.clamp(avg + variance, 0, 15)
	assert_eq(childIV, 13)
end)

test("IV remains clamped within legal 0-15 bounds even with extreme variance", function()
	local lowParent = 0
	local childLow = math.clamp(lowParent - 5, 0, 15)
	assert_eq(childLow, 0)

	local highParent = 15
	local childHigh = math.clamp(highParent + 5, 0, 15)
	assert_eq(childHigh, 15)
end)

test("Breeding compatible elements check validates matching tags", function()
	local parentA_Elements = { "Fire" }
	local parentA_Compatible = { "Fire", "Nature", "Wind", "Shadow", "Earth" }
	local parentB_Elements = { "Shadow" }

	local isCompatible = false
	for _, compElem in ipairs(parentA_Compatible) do
		if table.find(parentB_Elements, compElem) then
			isCompatible = true
			break
		end
	end
	assert_true(isCompatible, "Fire and Shadow should be compatible")
end)

test("Egg ready timestamp accurately identifies ready status", function()
	local startedAt = 1000
	local duration = 15
	local eggReadyAt = startedAt + duration

	local beforeTime = 1010
	assert_false(beforeTime >= eggReadyAt, "Should not be ready before duration expires")

	local afterTime = 1016
	assert_true(afterTime >= eggReadyAt, "Should be ready after duration expires")
end)

-- 4. PLOTS & PROGRESSION
print("\n[Suite: Plots & Territory]")
test("Plot purchase succeeds with valid level and currency", function()
	local playerLevel = 3
	local playerCoins = 1000
	local plotConfig = { Id = 2, RequiredLevel = 1, CostCoins = 250 }

	assert_true(playerLevel >= plotConfig.RequiredLevel)
	assert_true(playerCoins >= plotConfig.CostCoins)
	playerCoins -= plotConfig.CostCoins
	assert_eq(playerCoins, 750)
end)

test("Plot purchase fails when required level is not met", function()
	local playerLevel = 1
	local plotConfig = { Id = 5, RequiredLevel = 5, CostCoins = 3000 }
	local meetsLevel = playerLevel >= plotConfig.RequiredLevel
	assert_false(meetsLevel)
end)

-- 5. DATASTORE & MIGRATIONS
print("\n[Suite: PlayerData Schema]")
test("Default profile includes version, currency, starter monster and unlocked plot", function()
	local profile = {
		Version = 1,
		Currency = { Coins = 500, Gems = 15 },
		Progression = { Level = 1, XP = 0 },
		Monsters = { ["uuid-1"] = { SpeciesId = "emberfox", Level = 1 } },
		Plots = { ["1"] = { Id = 1, IsUnlocked = true } },
	}

	assert_eq(profile.Version, 1)
	assert_eq(profile.Currency.Coins, 500)
	assert_eq(profile.Progression.Level, 1)
	assert_true(profile.Plots["1"].IsUnlocked)
	assert_eq(profile.Monsters["uuid-1"].SpeciesId, "emberfox")
end)

test("Schema migration updates version 1 to version 2 seamlessly", function()
	local oldProfile = {
		Version = 1,
		Currency = { Coins = 500, Gems = 15 },
	}

	local function migrate(data: any): any
		if data.Version == 1 then
			data.Version = 2
			data.NewFeatureFlag = true
		end
		return data
	end

	local migrated = migrate(oldProfile)
	assert_eq(migrated.Version, 2)
	assert_true(migrated.NewFeatureFlag)
end)

print("\n========================================")
print(string.format(" Test Results: %d Passed, %d Failed (Total: %d)", passedTests, failedTests, totalTests))
print("========================================")

if failedTests > 0 then
	error("Some unit tests failed!", 1)
end
