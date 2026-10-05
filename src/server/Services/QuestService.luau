--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)

local PlayerDataService: any = nil
local EconomyService: any = nil

export type Quest = {
	Id: string,
	Title: string,
	Description: string,
	RewardCoins: number,
	RewardGems: number,
	RewardXP: number,
}

local QUESTS: { [string]: Quest } = {
	Quest_Plot = {
		Id = "Quest_Plot",
		Title = "Island Expansion",
		Description = "Unlock or purchase your second plot to expand your territory.",
		RewardCoins = 150,
		RewardGems = 2,
		RewardXP = 50,
	},
	Quest_Breed = {
		Id = "Quest_Breed",
		Title = "Master Breeder",
		Description = "Successfully breed two compatible monsters to hatch a new creature.",
		RewardCoins = 200,
		RewardGems = 3,
		RewardXP = 75,
	},
	Quest_Battle = {
		Id = "Quest_Battle",
		Title = "First Victory",
		Description = "Engage in an arena combat and claim victory.",
		RewardCoins = 250,
		RewardGems = 5,
		RewardXP = 100,
	},
}

local QuestService = {}

function QuestService:Init()
	Logger:Info("QUEST", "Initializing QuestService...")
	PlayerDataService = require(script.Parent.PlayerDataService)
	EconomyService = require(script.Parent.EconomyService)

	Network.HandleFunction("GetActiveQuests", function(player: Player)
		return QUESTS
	end)
end

function QuestService:Start()
	-- Ready
end

function QuestService:CompleteQuest(player: Player, questId: string): boolean
	local quest = QUESTS[questId]
	if not quest then return false end

	Logger:Info("QUEST", "Player %s completed quest: %s", player.Name, quest.Title)
	if quest.RewardCoins > 0 then
		EconomyService:AddCoins(player, quest.RewardCoins, "Quest: " .. quest.Title)
	end
	if quest.RewardGems > 0 then
		EconomyService:AddGems(player, quest.RewardGems, "Quest: " .. quest.Title)
	end

	Network.FireClient("QuestCompleted", player, quest)
	return true
end

return QuestService
