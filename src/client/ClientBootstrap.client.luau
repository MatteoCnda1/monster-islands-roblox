--!strict
-- ClientBootstrap: Master entry point for Monster Islands client

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local controllersFolder = script.Parent.Controllers

local UIController = require(controllersFolder.UIController)
local CombatController = require(controllersFolder.CombatController)
local PlotController = require(controllersFolder.PlotController)
local MonsterController = require(controllersFolder.MonsterController)
local CameraController = require(controllersFolder.CameraController)

local controllers = {
	UIController,
	CombatController,
	PlotController,
	MonsterController,
	CameraController,
}

Logger:Info("BOOTSTRAP", "Bootstrapping Monster Islands Client...")

-- Init phase
for _, controller in ipairs(controllers) do
	if typeof(controller.Init) == "function" then
		controller:Init()
	end
end

-- Start phase
for _, controller in ipairs(controllers) do
	if typeof(controller.Start) == "function" then
		controller:Start()
	end
end

Logger:Info("BOOTSTRAP", "=== Monster Islands Client Ready ===")
