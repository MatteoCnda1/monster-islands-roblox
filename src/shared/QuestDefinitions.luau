--!strict
-- One-time progression quests. Completion is tracked per player in PlayerData.CompletedQuests
-- and driven server-side by QuestService (game event signals from Plot/Breeding/Combat services).
local Types = require(script.Parent.Types)

-- Ordered list: defines the display order in the client Quests tab
local QuestList: { Types.QuestDefinition } = {
	{
		Id = "Quest_Plot",
		Title = "Island Expansion",
		Description = "Unlock or purchase your second plot to expand your territory.",
		RewardCoins = 150,
		RewardGems = 2,
		RewardXP = 50,
	},
	{
		Id = "Quest_Breed",
		Title = "Master Breeder",
		Description = "Successfully breed two compatible monsters to hatch a new creature.",
		RewardCoins = 200,
		RewardGems = 3,
		RewardXP = 75,
	},
	{
		Id = "Quest_Battle",
		Title = "First Victory",
		Description = "Engage in an arena combat and claim victory.",
		RewardCoins = 250,
		RewardGems = 5,
		RewardXP = 100,
	},
}

local questsById: { [string]: Types.QuestDefinition } = {}
for _, quest in ipairs(QuestList) do
	questsById[quest.Id] = quest
end

local QuestDefinitions = {}

function QuestDefinitions.Get(id: string): Types.QuestDefinition?
	return questsById[id]
end

function QuestDefinitions.GetAll(): { Types.QuestDefinition }
	return QuestList
end

return QuestDefinitions
