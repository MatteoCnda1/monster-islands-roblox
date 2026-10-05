--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)

local CombatService: any = nil

local waitingQueue: { Player } = {}

local MatchmakingService = {}

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
end

function MatchmakingService:Start()
	Players.PlayerRemoving:Connect(function(player)
		self:LeaveQueue(player)
	end)
end

function MatchmakingService:JoinQueue(player: Player): (boolean, string?)
	if table.find(waitingQueue, player) then
		return false, "Already in queue"
	end

	table.insert(waitingQueue, player)
	Logger:Info("PVP", "Player %s joined PvP matchmaking queue (Total waiting: %d)", player.Name, #waitingQueue)
	Network.FireClient("QueueStatusChanged", player, { InQueue = true, QueueCount = #waitingQueue })

	-- If at least 2 players are waiting, pair the first two!
	if #waitingQueue >= 2 then
		local p1 = table.remove(waitingQueue, 1)!
		local p2 = table.remove(waitingQueue, 1)!

		Network.FireClient("QueueStatusChanged", p1, { InQueue = false, Matched = true })
		Network.FireClient("QueueStatusChanged", p2, { InQueue = false, Matched = true })

		Logger:Info("PVP", "Matched %s vs %s for PvP battle!", p1.Name, p2.Name)
		local success, err = CombatService:CreateBattle(p1, p2, false)
		if not success then
			Logger:Error("PVP", "Failed to start battle for %s and %s: %s", p1.Name, p2.Name, tostring(err))
		end
	end

	return true, nil
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
