--!strict
-- Pure player progression rules: XP curve and level-ups (no Roblox services, no side effects).
-- Used by PlayerDataService:AddPlayerXP (server), the HUD (client) and tests/run_tests.luau.
--
-- Profile semantics: `Progression.XP` is the XP accumulated INSIDE the current level
-- (0 <= XP < GetXPToNextLevel(Level)); it is reset (minus the overflow) on each level-up.
-- The curve parameters live in Config.PROGRESSION (see the rationale there).
local Config = require(script.Parent.Config)

local ProgressionMath = {}

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function ProgressionMath.GetMaxLevel(): number
	return Config.PROGRESSION.MAX_LEVEL
end

-- Clamps any stored level to an integer in [1, MAX_LEVEL] (garbage -> 1).
function ProgressionMath.SanitizeLevel(level: any): number
	if not isFiniteNumber(level) then
		return 1
	end
	return math.clamp(math.floor(level), 1, ProgressionMath.GetMaxLevel())
end

-- XP needed to go from `level` to `level + 1` (linear: BASE + INCREMENT * (level - 1)).
-- Returns 0 at (or above) the max level: there is no next level.
function ProgressionMath.GetXPToNextLevel(level: number): number
	local lvl = ProgressionMath.SanitizeLevel(level)
	if lvl >= ProgressionMath.GetMaxLevel() then
		return 0
	end
	local curve = Config.PROGRESSION
	return curve.BASE_XP_TO_LEVEL_UP + curve.XP_INCREMENT_PER_LEVEL * (lvl - 1)
end

-- Total XP earned from a fresh level 1 profile to reach `level` (GetTotalXPForLevel(1) == 0).
function ProgressionMath.GetTotalXPForLevel(level: number): number
	local target = ProgressionMath.SanitizeLevel(level)
	local total = 0
	for lvl = 1, target - 1 do
		total += ProgressionMath.GetXPToNextLevel(lvl)
	end
	return total
end

-- An XP gain is valid when it is a finite number worth at least 1 XP once floored
-- (rejects 0, negatives, fractions below 1, NaN, ±inf and non-numbers).
function ProgressionMath.IsValidXPAmount(amount: any): boolean
	return isFiniteNumber(amount) and math.floor(amount) >= 1
end

-- Applies an XP gain to a (level, xp) pair and returns (newLevel, newXP, levelsGained).
-- Several level-ups can happen at once. At the max level the XP stays at 0 (overflow discarded).
-- An invalid amount adds no XP (the state is still sanitized and normalized: a stored XP already
-- above the threshold, e.g. from an older profile, is converted into the level-ups it is worth).
function ProgressionMath.ApplyXP(level: any, xp: any, amount: any): (number, number, number)
	local startLevel = ProgressionMath.SanitizeLevel(level)
	local currentLevel = startLevel
	local currentXP = if isFiniteNumber(xp) then math.max(0, math.floor(xp)) else 0

	if ProgressionMath.IsValidXPAmount(amount) then
		currentXP += math.floor(amount)
	end

	local maxLevel = ProgressionMath.GetMaxLevel()
	while currentLevel < maxLevel do
		local needed = ProgressionMath.GetXPToNextLevel(currentLevel)
		if currentXP < needed then
			break
		end
		currentXP -= needed
		currentLevel += 1
	end
	if currentLevel >= maxLevel then
		currentXP = 0
	end

	return currentLevel, currentXP, currentLevel - startLevel
end

return ProgressionMath
