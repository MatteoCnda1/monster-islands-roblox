--!strict
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local CameraController = {
	Camera = Workspace.CurrentCamera,
}

function CameraController:Init()
	Logger:Info("CAMERA", "Initializing CameraController...")
end

function CameraController:Start()
	-- Ready
end

function CameraController:FocusOnPosition(targetPos: Vector3, duration: number)
	if not self.Camera then return end
	local startCFrame = self.Camera.CFrame
	local endCFrame = CFrame.new(targetPos + Vector3.new(0, 15, 25), targetPos)
	local tween = TweenService:Create(self.Camera, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = endCFrame,
	})
	tween:Play()
end

return CameraController
