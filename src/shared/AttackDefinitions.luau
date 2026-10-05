--!strict
local Types = require(script.Parent.Types)

local Attacks: { [string]: Types.AttackDefinition } = {
	FlameBurst = {
		Id = "FlameBurst",
		DisplayName = "Flame Burst",
		Description = "Shoots a burst of roaring flame that may inflict Burn on the opponent.",
		Element = "Fire",
		Power = 45,
		Accuracy = 95,
		Priority = 0,
		CooldownTurns = 0,
		EffectType = "Burn",
		EffectChance = 30,
		EffectDuration = 3,
	},

	QuickStrike = {
		Id = "QuickStrike",
		DisplayName = "Quick Strike",
		Description = "A lightning-fast lunging attack that strikes with high priority.",
		Element = "Wind",
		Power = 35,
		Accuracy = 100,
		Priority = 1,
		CooldownTurns = 0,
		EffectType = "Damage",
	},

	BrambleSlam = {
		Id = "BrambleSlam",
		DisplayName = "Bramble Slam",
		Description = "Strikes the foe with heavy thorned branches dealing heavy Nature damage.",
		Element = "Nature",
		Power = 50,
		Accuracy = 90,
		Priority = 0,
		CooldownTurns = 0,
		EffectType = "Damage",
	},

	StoneShield = {
		Id = "StoneShield",
		DisplayName = "Stone Shield",
		Description = "Covers the monster in thick granite armor, reducing damage taken for 1 turn.",
		Element = "Earth",
		Power = 0,
		Accuracy = 100,
		Priority = 2,
		CooldownTurns = 1,
		EffectType = "Shield",
		EffectDuration = 1,
	},

	WaterSurge = {
		Id = "WaterSurge",
		DisplayName = "Water Surge",
		Description = "Summons a cascading torrent of pressurized water against the enemy.",
		Element = "Water",
		Power = 48,
		Accuracy = 95,
		Priority = 0,
		CooldownTurns = 0,
		EffectType = "Damage",
	},

	BubbleGuard = {
		Id = "BubbleGuard",
		DisplayName = "Bubble Guard",
		Description = "Envelops the user in a buoyant protective bubble that absorbs incoming damage.",
		Element = "Water",
		Power = 0,
		Accuracy = 100,
		Priority = 2,
		CooldownTurns = 1,
		EffectType = "Shield",
		EffectDuration = 1,
	},

	GaleSlash = {
		Id = "GaleSlash",
		DisplayName = "Gale Slash",
		Description = "Whips razor-sharp air currents at the target with high speed.",
		Element = "Wind",
		Power = 48,
		Accuracy = 92,
		Priority = 0,
		CooldownTurns = 0,
		EffectType = "Damage",
	},

	Tailwind = {
		Id = "Tailwind",
		DisplayName = "Tailwind",
		Description = "Summons favorable air currents that boost the monster's speed for 2 turns.",
		Element = "Wind",
		Power = 0,
		Accuracy = 100,
		Priority = 1,
		CooldownTurns = 2,
		EffectType = "SpeedBoost",
		EffectDuration = 2,
	},

	ShadowClaw = {
		Id = "ShadowClaw",
		DisplayName = "Shadow Claw",
		Description = "Slashes with shadowy claws that pierce through standard defenses.",
		Element = "Shadow",
		Power = 55,
		Accuracy = 90,
		Priority = 0,
		CooldownTurns = 0,
		EffectType = "Damage",
	},

	VoidPulse = {
		Id = "VoidPulse",
		DisplayName = "Void Pulse",
		Description = "Releases a shockwave of dark arcane energy with immense destructive potential.",
		Element = "Shadow",
		Power = 65,
		Accuracy = 85,
		Priority = 0,
		CooldownTurns = 2,
		EffectType = "Damage",
	},
}

local AttackDefinitions = {}

function AttackDefinitions.Get(id: string): Types.AttackDefinition?
	return Attacks[id]
end

function AttackDefinitions.GetAll(): { [string]: Types.AttackDefinition }
	return Attacks
end

return AttackDefinitions
