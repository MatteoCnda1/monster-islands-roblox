--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)

local PlotController = {}

function PlotController:Init()
	Logger:Info("PLOT", "Initializing PlotController...")
end

function PlotController:Start()
	-- Request server to refresh plot visual state for this client
	task.wait(1)
	Network.FireServer("RefreshPlotsRequest")
end

return PlotController
