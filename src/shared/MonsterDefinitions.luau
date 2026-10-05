--!strict
local Types = require(script.Parent.Types)

local Monsters: { [string]: Types.MonsterDefinition } = {
	emberfox = {
		Id = "emberfox",
		DisplayName = "Emberfox",
		Description = "A spirited volcanic fox whose bushy fiery tail blazes brighter when preparing to strike.",
		Rarity = "Rare",
		Elements = { "Fire" },
		BaseStats = {
			Health = 95,
			Attack = 28,
			Defense = 14,
			Speed = 24,
		},
		Growth = {
			Health = 9,
			Attack = 4.2,
			Defense = 2.2,
			Speed = 3.5,
		},
		Breeding = {
			CompatibleElements = { "Fire", "Nature", "Wind", "Shadow", "Earth" },
			BreedingTime = 15,
			IncubationTime = 10,
		},
		Skills = { "FlameBurst", "QuickStrike" },
		PrimaryColor = Color3.fromRGB(235, 75, 30),
		SecondaryColor = Color3.fromRGB(255, 180, 50),
		ScaleMultiplier = 1.0,
	},

	mossaur = {
		Id = "mossaur",
		DisplayName = "Mossaur",
		Description = "A colossal ancient reptile armored with thick moss-covered stone plates and robust stamina.",
		Rarity = "Uncommon",
		Elements = { "Nature", "Earth" },
		BaseStats = {
			Health = 135,
			Attack = 20,
			Defense = 26,
			Speed = 12,
		},
		Growth = {
			Health = 14,
			Attack = 2.8,
			Defense = 4.5,
			Speed = 1.4,
		},
		Breeding = {
			CompatibleElements = { "Nature", "Earth", "Water", "Fire" },
			BreedingTime = 15,
			IncubationTime = 10,
		},
		Skills = { "BrambleSlam", "StoneShield" },
		PrimaryColor = Color3.fromRGB(45, 130, 60),
		SecondaryColor = Color3.fromRGB(130, 95, 50),
		ScaleMultiplier = 1.35,
	},

	aquaphin = {
		Id = "aquaphin",
		DisplayName = "Aquaphin",
		Description = "A sleek, hydrodynamic swimmer that glides gracefully through torrents and creates protective bubble shields.",
		Rarity = "Rare",
		Elements = { "Water" },
		BaseStats = {
			Health = 105,
			Attack = 24,
			Defense = 18,
			Speed = 22,
		},
		Growth = {
			Health = 10,
			Attack = 3.5,
			Defense = 2.8,
			Speed = 3.0,
		},
		Breeding = {
			CompatibleElements = { "Water", "Nature", "Wind", "Earth" },
			BreedingTime = 15,
			IncubationTime = 10,
		},
		Skills = { "WaterSurge", "BubbleGuard" },
		PrimaryColor = Color3.fromRGB(35, 145, 235),
		SecondaryColor = Color3.fromRGB(150, 230, 255),
		ScaleMultiplier = 1.1,
	},

	zephlyn = {
		Id = "zephlyn",
		DisplayName = "Zephlyn",
		Description = "An agile avian-dragon that rides high-altitude thermal winds and delivers swift gale-force strikes.",
		Rarity = "Rare",
		Elements = { "Wind" },
		BaseStats = {
			Health = 90,
			Attack = 26,
			Defense = 13,
			Speed = 28,
		},
		Growth = {
			Health = 8,
			Attack = 3.9,
			Defense = 2.0,
			Speed = 4.2,
		},
		Breeding = {
			CompatibleElements = { "Wind", "Fire", "Water", "Shadow" },
			BreedingTime = 15,
			IncubationTime = 10,
		},
		Skills = { "GaleSlash", "Tailwind" },
		PrimaryColor = Color3.fromRGB(70, 210, 205),
		SecondaryColor = Color3.fromRGB(240, 255, 255),
		ScaleMultiplier = 0.95,
	},

	noctyra = {
		Id = "noctyra",
		DisplayName = "Noctyra",
		Description = "A stealthy winged panther prowling within twilight shadows, unleashing devastating void-infused strikes.",
		Rarity = "Epic",
		Elements = { "Shadow" },
		BaseStats = {
			Health = 98,
			Attack = 32,
			Defense = 15,
			Speed = 25,
		},
		Growth = {
			Health = 9.5,
			Attack = 4.8,
			Defense = 2.3,
			Speed = 3.6,
		},
		Breeding = {
			CompatibleElements = { "Shadow", "Fire", "Wind" },
			BreedingTime = 20,
			IncubationTime = 12,
		},
		Skills = { "ShadowClaw", "VoidPulse" },
		PrimaryColor = Color3.fromRGB(75, 30, 130),
		SecondaryColor = Color3.fromRGB(180, 80, 240),
		ScaleMultiplier = 1.15,
	},

	-- Special discovery / mutation species
	voidfox = {
		Id = "voidfox",
		DisplayName = "Voidfox",
		Description = "A legendary mutation born from Fire and Shadow. Its ghostly dark flames burn through all matter.",
		Rarity = "Legendary",
		Elements = { "Fire", "Shadow" },
		BaseStats = {
			Health = 115,
			Attack = 36,
			Defense = 19,
			Speed = 29,
		},
		Growth = {
			Health = 11,
			Attack = 5.2,
			Defense = 2.9,
			Speed = 4.0,
		},
		Breeding = {
			CompatibleElements = { "Fire", "Shadow" },
			BreedingTime = 30,
			IncubationTime = 15,
		},
		Skills = { "FlameBurst", "VoidPulse" },
		PrimaryColor = Color3.fromRGB(30, 20, 45),
		SecondaryColor = Color3.fromRGB(255, 90, 160),
		ScaleMultiplier = 1.2,
	},
}

local MonsterDefinitions = {}

function MonsterDefinitions.Get(speciesId: string): Types.MonsterDefinition?
	return Monsters[speciesId]
end

function MonsterDefinitions.GetAll(): { [string]: Types.MonsterDefinition }
	return Monsters
end

function MonsterDefinitions.CalculateStats(speciesId: string, level: number, ivs: Types.MonsterIVs): (Types.Stats, number)
	local def = Monsters[speciesId]
	if not def then
		error(string.format("Species %s not found in MonsterDefinitions", tostring(speciesId)))
	end

	local lvlBonus = level - 1
	local attack = math.floor(def.BaseStats.Attack + (def.Growth.Attack * lvlBonus) + (ivs.Attack or 0))
	local defense = math.floor(def.BaseStats.Defense + (def.Growth.Defense * lvlBonus) + (ivs.Defense or 0))
	local speed = math.floor(def.BaseStats.Speed + (def.Growth.Speed * lvlBonus) + (ivs.Speed or 0))

	local maxHealth = math.floor((def.BaseStats.Health * 2) + (def.Growth.Health * lvlBonus * 1.5) + ((ivs.Health or 0) * 3))

	local calculatedStats: Types.Stats = {
		Health = maxHealth,
		Attack = math.max(1, attack),
		Defense = math.max(1, defense),
		Speed = math.max(1, speed),
	}

	return calculatedStats, maxHealth
end

return MonsterDefinitions
