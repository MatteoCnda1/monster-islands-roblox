--!strict
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local localPlayer = Players.LocalPlayer

local CameraController = {
	Camera = Workspace.CurrentCamera,
}

function CameraController:Init()
	Logger:Info("CAMERA", "Initializing CameraController...")
	self.Camera = Workspace.CurrentCamera
end

function CameraController:Start()
	-- Ready
end

function CameraController:FocusOnPosition(targetPos: Vector3, duration: number?)
	local camera = Workspace.CurrentCamera
	if not camera then return end

	camera.CameraType = Enum.CameraType.Scriptable
	local endCFrame = CFrame.new(targetPos + Vector3.new(0, 14, 26), targetPos)
	local tween = TweenService:Create(camera, TweenInfo.new(duration or 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = endCFrame,
	})
	tween:Play()
end

function CameraController:FocusOnBattle(arenaCenter: Vector3)
	local camera = Workspace.CurrentCamera
	if not camera then return end

	camera.CameraType = Enum.CameraType.Scriptable
	-- Cinematic wide isometric perspective of the arena
	local eyePos = arenaCenter + Vector3.new(0, 16, 32)
	local endCFrame = CFrame.new(eyePos, arenaCenter)
	local tween = TweenService:Create(camera, TweenInfo.new(0.8, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
		CFrame = endCFrame,
	})
	tween:Play()
end

function CameraController:FocusOnCombatant(targetPos: Vector3, offset: Vector3?)
	local camera = Workspace.CurrentCamera
	if not camera then return end

	camera.CameraType = Enum.CameraType.Scriptable
	local eyePos = targetPos + (offset or Vector3.new(0, 7, 14))
	local endCFrame = CFrame.new(eyePos, targetPos + Vector3.new(0, 1.5, 0))
	local tween = TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = endCFrame,
	})
	tween:Play()
end

function CameraController:ResetToPlayer()
	local camera = Workspace.CurrentCamera
	if not camera then return end

	local char = localPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

return CameraController
