--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)
local MatchmakingRules = require(ReplicatedStorage.Shared.MatchmakingRules)

local CombatService: any = nil

local waitingQueue: { Player } = {}

-- "QueueStatusChanged" payloads (contract handled by UIController:SetPvPQueueStatus)
local MATCH_FAILED_STATUS = { InQueue = false, Matched = false, Error = "Match could not start, please queue again" }
local ALREADY_IN_BATTLE_STATUS = { InQueue = false, Matched = false, Error = "Removed from the PvP queue: you are already in a battle" }
local REQUEUED_MESSAGE = "Your opponent could not join. You are back at the front of the queue"

local MatchmakingService = {}

-- A queued player can be paired only if still connected and not already in a battle
local function isEligible(player: Player): boolean
	return player.Parent == Players and not CombatService:IsInBattle(player)
end

local function putBackAtHead(players: { Player })
	-- Insert in reverse so that `players` keeps its order at the head of the queue
	for i = #players, 1, -1 do
		table.insert(waitingQueue, 1, players[i])
	end
end

function MatchmakingService:Init()
	Logger:Info("PVP", "Initializing MatchmakingService...")
	CombatService = require(script.Parent.CombatService)

	-- Remotes
	Network.HandleFunction("JoinPvPQueue", function(player: Player)
		return self:JoinQueue(player)
	end)

	Network.HandleFunction("LeavePvPQueue", function(player: Player)
		return self:LeaveQueue(player)
	end)

	-- Any battle start (bot practice included) takes the player out of the queue (issue #31)
	CombatService.BattleStartedSignal:Connect(function(player: Player, _battleId: string)
		self:LeaveQueue(player)
	end)
end

function MatchmakingService:Start()
	Players.PlayerRemoving:Connect(function(player)
		self:LeaveQueue(player)
	end)
end

function MatchmakingService:JoinQueue(player: Player): (boolean, string?)
	if CombatService:IsInBattle(player) then
		return false, "Already in a battle"
	end
	if table.find(waitingQueue, player) then
		return false, "Already in queue"
	end

	table.insert(waitingQueue, player)
	Logger:Info("PVP", "Player %s joined PvP matchmaking queue (Total waiting: %d)", player.Name, #waitingQueue)
	Network.FireClient("QueueStatusChanged", player, { InQueue = true, QueueCount = #waitingQueue })

	self:_matchWaitingPlayers()
	return true, nil
end

-- Pairs the players at the head of the queue while at least two are waiting. Every iteration removes
-- at least one player from the queue for good (battle started or player dropped), so the loop ends.
function MatchmakingService:_matchWaitingPlayers()
	while #waitingQueue >= 2 do
		local p1 = table.remove(waitingQueue, 1) :: Player
		local p2 = table.remove(waitingQueue, 1) :: Player
		local pair = { p1, p2 }

		-- 1. Re-check both players right before pairing them
		local resolution = MatchmakingRules.ResolvePair(isEligible(p1), isEligible(p2))
		if not resolution.StartBattle then
			for _, slot in ipairs(resolution.Dropped) do
				local dropped = pair[slot]
				Logger:Warn("PVP", "Dropping %s from PvP queue: no longer eligible (in battle or disconnected)", dropped.Name)
				if dropped.Parent == Players then
					Network.FireClient("QueueStatusChanged", dropped, ALREADY_IN_BATTLE_STATUS)
				end
			end
			-- The remaining player never left the queue from the client's point of view: nothing to send
			local requeued: { Player } = {}
			for _, slot in ipairs(resolution.Requeue) do
				table.insert(requeued, pair[slot])
			end
			putBackAtHead(requeued)
			continue
		end

		-- 2. Both eligible: start the battle
		Network.FireClient("QueueStatusChanged", p1, { InQueue = false, Matched = true })
		Network.FireClient("QueueStatusChanged", p2, { InQueue = false, Matched = true })

		Logger:Info("PVP", "Matched %s vs %s for PvP battle!", p1.Name, p2.Name)
		local ok, success, err, blamed = pcall(CombatService.CreateBattle, CombatService, p1, p2, false)
		if not ok then
			-- CreateBattle threw: treat it as a failure nobody can be blamed for
			success, err, blamed = false, success, nil
		end
		if success then
			continue
		end

		-- 3. Battle creation failed: do not penalise the player who is not responsible
		Logger:Error("PVP", "Failed to start battle for %s and %s: %s (blamed: %s)",
			p1.Name, p2.Name, tostring(err), blamed and blamed.Name or "unknown")
		local blamedSlot: number? = if blamed == p1 then 1 elseif blamed == p2 then 2 else nil
		local failure = MatchmakingRules.ResolveFailedBattle(isEligible(p1), isEligible(p2), blamedSlot)

		local requeued: { Player } = {}
		for _, slot in ipairs(failure.Requeue) do
			table.insert(requeued, pair[slot])
		end
		putBackAtHead(requeued)

		for _, player in ipairs(requeued) do
			Logger:Info("PVP", "Player %s put back at the head of the PvP queue", player.Name)
			Network.FireClient("QueueStatusChanged", player, {
				InQueue = true,
				QueueCount = #waitingQueue,
				Error = REQUEUED_MESSAGE,
			})
		end
		for _, slot in ipairs(failure.Dropped) do
			local dropped = pair[slot]
			if dropped.Parent == Players then
				Network.FireClient("QueueStatusChanged", dropped, MATCH_FAILED_STATUS)
			end
		end
	end
end

function MatchmakingService:LeaveQueue(player: Player): boolean
	local idx = table.find(waitingQueue, player)
	if idx then
		table.remove(waitingQueue, idx)
		Logger:Info("PVP", "Player %s left PvP queue", player.Name)
		Network.FireClient("QueueStatusChanged", player, { InQueue = false })
		return true
	end
	return false
end

return MatchmakingService
