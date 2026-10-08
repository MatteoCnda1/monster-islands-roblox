--!strict
-- Pure combat formulas (no Roblox services, no side effects).
-- Used by CombatService and exercised directly by tests/run_tests.luau.
-- Randomness is injected (`random` behaves like math.random()) so tests can drive it.
local Config = require(script.Parent.Config)

local CombatMath = {}

CombatMath.PRIORITY_WEIGHT = 1000 -- One priority point outweighs any speed difference
CombatMath.SPEED_BOOST_MULTIPLIER = 1.3
CombatMath.SHIELD_DAMAGE_MULTIPLIER = 0.6 -- Shield absorbs 40% of incoming damage
CombatMath.BURN_MAX_HEALTH_FRACTION = 0.06
CombatMath.MIN_BURN_DAMAGE = 2

-- Turn order score: higher acts first. Priority dominates, speed breaks ties.
function CombatMath.GetActionOrderScore(priority: number, speed: number, hasSpeedBoost: boolean): number
	local effectiveSpeed = speed
	if hasSpeedBoost then
		effectiveSpeed = math.floor(speed * CombatMath.SPEED_BOOST_MULTIPLIER)
	end
	return (priority * CombatMath.PRIORITY_WEIGHT) + effectiveSpeed
end

-- Raw damage before elemental / critical / variance / shield modifiers.
function CombatMath.ComputeBaseDamage(level: number, power: number, attack: number, defense: number): number
	local def = math.max(1, defense)
	return (((2 * level / 5) + 2) * power * (attack / def) / 50) + 2
end

-- Final damage dealt: modifiers applied, floored, shield applied, never below 1.
function CombatMath.ComputeFinalDamage(
	baseDamage: number,
	elementMultiplier: number,
	isCritical: boolean,
	variance: number,
	isShielded: boolean
): number
	local critMult = if isCritical then Config.COMBAT.CRIT_DAMAGE_MULTIPLIER else 1.0
	local finalDamage = math.floor(baseDamage * elementMultiplier * critMult * variance)

	if isShielded then
		finalDamage = math.floor(finalDamage * CombatMath.SHIELD_DAMAGE_MULTIPLIER)
	end

	return math.max(1, finalDamage)
end

function CombatMath.RollIsCritical(random: () -> number): boolean
	return random() <= Config.COMBAT.BASE_CRIT_CHANCE
end

function CombatMath.RollVariance(random: () -> number): number
	local minV = Config.COMBAT.MIN_DAMAGE_VARIANCE
	local maxV = Config.COMBAT.MAX_DAMAGE_VARIANCE
	return minV + (random() * (maxV - minV))
end

-- End-of-turn burn damage for a monster with the given max health.
function CombatMath.ComputeBurnDamage(maxHealth: number): number
	return math.max(CombatMath.MIN_BURN_DAMAGE, math.floor(maxHealth * CombatMath.BURN_MAX_HEALTH_FRACTION))
end

-- Remaining health after taking damage, clamped to [0, maxHealth].
function CombatMath.ApplyDamage(currentHealth: number, damage: number, maxHealth: number): number
	return math.clamp(currentHealth - damage, 0, maxHealth)
end

return CombatMath
