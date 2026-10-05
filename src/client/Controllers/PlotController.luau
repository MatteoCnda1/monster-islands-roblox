--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)

local PlotController = {}

function PlotController:Init()
	Logger:Info("PLOT", "Initializing PlotController...")
	Network.OnClientEvent("DecorationPlaced", function(data: any)
		Logger:Info("PLOT", "Decoration placed: %s on Plot %s", data.Decoration and data.Decoration.DecorationId or "?", tostring(data.PlotId))
	end)
end

function PlotController:Start()
	-- Request server to refresh plot visual state and active breeding eggs for this client
	task.wait(1)
	Network.FireServer("RefreshPlotsRequest")
	Network.FireServer("RefreshBreedingEggs")
end

return PlotController
