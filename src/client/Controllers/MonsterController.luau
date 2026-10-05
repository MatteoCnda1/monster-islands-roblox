--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)

local MonsterController = {}

function MonsterController:Init()
	Logger:Info("MONSTER", "Initializing MonsterController...")
end

function MonsterController:Start()
	-- Request server to render placed monsters in workspace
	task.wait(1.5)
	Network.FireServer("RequestRenderPlacedMonsters")
end

return MonsterController
