--!strict
local Types = require(script.Parent.Types)

type ElementChartType = {
	[Types.ElementType]: {
		[Types.ElementType]: number,
	},
}

-- Effectiveness multipliers:
-- 1.5 = Super effective
-- 0.75 = Not very effective
-- 1.0 = Neutral (default)
local ElementChart: ElementChartType = {
	Fire = {
		Nature = 1.5,
		Wind = 1.25,
		Water = 0.75,
		Fire = 0.75,
	},
	Water = {
		Fire = 1.5,
		Earth = 1.5,
		Nature = 0.75,
		Water = 0.75,
	},
	Nature = {
		Earth = 1.5,
		Water = 1.25,
		Fire = 0.75,
		Nature = 0.75,
	},
	Earth = {
		Fire = 1.25,
		Wind = 1.5,
		Nature = 0.75,
		Water = 0.75,
	},
	Wind = {
		Nature = 1.5,
		Earth = 0.75,
		Wind = 0.75,
	},
	Shadow = {
		Light = 1.5,
		Arcane = 1.25,
		Shadow = 0.75,
	},
	Light = {
		Shadow = 1.5,
		Arcane = 0.75,
		Light = 0.75,
	},
	Arcane = {
		Fire = 1.2,
		Water = 1.2,
		Nature = 1.2,
		Earth = 1.2,
		Arcane = 0.8,
	},
}

local ElementColors: { [Types.ElementType]: Color3 } = {
	Fire = Color3.fromRGB(240, 80, 40),
	Water = Color3.fromRGB(40, 140, 240),
	Nature = Color3.fromRGB(50, 180, 80),
	Earth = Color3.fromRGB(160, 110, 60),
	Wind = Color3.fromRGB(80, 210, 200),
	Shadow = Color3.fromRGB(90, 40, 150),
	Light = Color3.fromRGB(250, 220, 80),
	Arcane = Color3.fromRGB(190, 60, 220),
}

local ElementDefinitions = {}

function ElementDefinitions.GetEffectiveness(attackerElement: Types.ElementType, defenderElement: Types.ElementType): number
	local attackerRow = ElementChart[attackerElement]
	if attackerRow and attackerRow[defenderElement] then
		return attackerRow[defenderElement]
	end
	return 1.0
end

function ElementDefinitions.GetElementColor(element: Types.ElementType): Color3
	return ElementColors[element] or Color3.fromRGB(200, 200, 200)
end

return ElementDefinitions
