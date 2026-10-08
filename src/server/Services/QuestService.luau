--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)
local QuestDefinitions = require(ReplicatedStorage.Shared.QuestDefinitions)

local PlayerDataService: any = nil
local EconomyService: any = nil

local QuestService = {}

function QuestService:Init()
	Logger:Info("QUEST", "Initializing QuestService...")
	PlayerDataService = require(script.Parent.PlayerDataService)
	EconomyService = require(script.Parent.EconomyService)

	-- Game event sources: emitters expose module-level signals and never depend on QuestService
	local PlotService = require(script.Parent.PlotService)
	local BreedingService = require(script.Parent.BreedingService)
	local CombatService = require(script.Parent.CombatService)

	PlotService.PlotPurchasedSignal:Connect(function(player: Player, _plotId: number)
		self:CompleteQuest(player, "Quest_Plot")
	end)

	BreedingService.EggHatchedSignal:Connect(function(player: Player, _monster: Types.MonsterInstance)
		self:CompleteQuest(player, "Quest_Breed")
	end)

	-- Bot practice victories count too, so a solo player can complete the quest
	CombatService.BattleWonSignal:Connect(function(player: Player, _wasAgainstBot: boolean)
		self:CompleteQuest(player, "Quest_Battle")
	end)

	Network.HandleFunction("GetActiveQuests", function(player: Player)
		local statuses = self:GetQuestStatuses(player)
		if not statuses then
			return false, "Player data not loaded"
		end
		return true, statuses
	end)
end

function QuestService:Start()
	-- Ready
end

function QuestService:IsQuestCompleted(player: Player, questId: string): boolean
	local profile = PlayerDataService:GetProfile(player)
	return profile ~= nil and profile.CompletedQuests ~= nil and profile.CompletedQuests[questId] ~= nil
end

-- Returns every quest definition with this player's completion state, in display order
function QuestService:GetQuestStatuses(player: Player): { Types.QuestStatus }?
	local profile: Types.PlayerData? = PlayerDataService:GetProfile(player)
	if not profile then return nil end

	local completed = profile.CompletedQuests or {}
	local statuses: { Types.QuestStatus } = {}
	for _, quest in ipairs(QuestDefinitions.GetAll()) do
		local completedAt = completed[quest.Id]
		table.insert(statuses, {
			Id = quest.Id,
			Title = quest.Title,
			Description = quest.Description,
			RewardCoins = quest.RewardCoins,
			RewardGems = quest.RewardGems,
			RewardXP = quest.RewardXP,
			IsCompleted = completedAt ~= nil,
			CompletedAt = completedAt,
		})
	end
	return statuses
end

-- Idempotent: a quest is rewarded at most once per player (persisted in PlayerData.CompletedQuests).
-- Returns true only when this call actually completed the quest.
function QuestService:CompleteQuest(player: Player, questId: string): boolean
	local quest = QuestDefinitions.Get(questId)
	if not quest then
		Logger:Warn("QUEST", "Attempted to complete unknown quest '%s' for %s", tostring(questId), player.Name)
		return false
	end

	-- Fast path: avoid a useless profile sync to the client for already completed quests
	if self:IsQuestCompleted(player, questId) then
		return false
	end

	-- Check-and-mark atomically (the updater never yields) BEFORE granting any reward,
	-- so concurrent triggers cannot reward the same quest twice.
	local newlyCompleted = false
	local updated = PlayerDataService:UpdateProfile(player, function(profile: Types.PlayerData)
		if not profile.CompletedQuests then
			profile.CompletedQuests = {}
		end
		if profile.CompletedQuests[questId] ~= nil then
			return
		end
		profile.CompletedQuests[questId] = os.time()
		if quest.RewardXP > 0 then
			profile.Progression.XP += quest.RewardXP
		end
		newlyCompleted = true
	end)

	if not updated or not newlyCompleted then
		return false
	end

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
