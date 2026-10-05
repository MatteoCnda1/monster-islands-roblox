--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)
local AttackDefinitions = require(ReplicatedStorage.Shared.AttackDefinitions)
local MonsterDefinitions = require(ReplicatedStorage.Shared.MonsterDefinitions)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

local CombatController = {
	BattleOverlay = nil :: Frame?,
	IsActive = false,
	CurrentBattleId = nil :: string?,
	YourActiveMonster = nil :: Types.MonsterInstance?,
	OpponentActiveMonster = nil :: Types.MonsterInstance?,
	LogLabel = nil :: TextLabel?,
	TimerLabel = nil :: TextLabel?,
	YourHPBar = nil :: Frame?,
	YourHPText = nil :: TextLabel?,
	OpponentHPBar = nil :: Frame?,
	OpponentHPText = nil :: TextLabel?,
	SkillsContainer = nil :: Frame?,
}

local function createRoundedCorner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

function CombatController:Init()
	Logger:Info("COMBAT", "Initializing CombatController...")

	Network.OnClientEvent("BattleStarted", function(data: any)
		self:OnBattleStarted(data)
	end)

	Network.OnClientEvent("BattleTurnReport", function(report: Types.TurnReport)
		self:OnTurnReport(report)
	end)

	Network.OnClientEvent("BattleEnded", function(result: any)
		self:OnBattleEnded(result)
	end)
end

function CombatController:Start()
	-- Ready
end

function CombatController:OnBattleStarted(data: any)
	self.IsActive = true
	self.CurrentBattleId = data.BattleId
	self.YourActiveMonster = data.YourTeam[data.YourActiveIndex or 1]
	self.OpponentActiveMonster = data.OpponentActiveMonster

	self:_buildBattleOverlay(data)
	Logger:Info("COMBAT", "Battle overlay opened for battle %s vs %s", data.BattleId, data.OpponentName)
end

function CombatController:_buildBattleOverlay(data: any)
	local screenGui = playerGui:FindFirstChild("MonsterIslandsGui") :: ScreenGui
	if not screenGui then return end

	local existing = screenGui:FindFirstChild("BattleOverlay")
	if existing then existing:Destroy() end

	local overlay = Instance.new("Frame")
	overlay.Name = "BattleOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
	overlay.Parent = screenGui
	self.BattleOverlay = overlay

	-- 1. Opponent Status Plate (Top Right)
	local oppPlate = Instance.new("Frame")
	oppPlate.Size = UDim2.new(0, 320, 0, 80)
	oppPlate.Position = UDim2.new(1, -340, 0, 80)
	oppPlate.BackgroundColor3 = Color3.fromRGB(30, 25, 35)
	oppPlate.Parent = overlay
	createRoundedCorner(oppPlate, 12)

	local oppName = Instance.new("TextLabel")
	oppName.Size = UDim2.new(1, -20, 0, 26)
	oppName.Position = UDim2.new(0, 10, 0, 8)
	oppName.BackgroundTransparency = 1
	oppName.Text = string.format("%s (%s)", self.OpponentActiveMonster and self.OpponentActiveMonster.Nickname or "Opponent", data.OpponentName)
	oppName.TextColor3 = Color3.fromRGB(255, 100, 100)
	oppName.Font = Enum.Font.GothamBold
	oppName.TextScaled = true
	oppName.TextXAlignment = Enum.TextXAlignment.Left
	oppName.Parent = oppPlate

	local oppHPBg = Instance.new("Frame")
	oppHPBg.Size = UDim2.new(1, -20, 0, 18)
	oppHPBg.Position = UDim2.new(0, 10, 0, 42)
	oppHPBg.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	oppHPBg.Parent = oppPlate
	createRoundedCorner(oppHPBg, 6)

	local oppHPFill = Instance.new("Frame")
	oppHPFill.Size = UDim2.new(1, 0, 1, 0)
	oppHPFill.BackgroundColor3 = Color3.fromRGB(240, 70, 70)
	oppHPFill.Parent = oppHPBg
	createRoundedCorner(oppHPFill, 6)
	self.OpponentHPBar = oppHPFill

	local oppHPText = Instance.new("TextLabel")
	oppHPText.Size = UDim2.new(1, 0, 1, 0)
	oppHPText.BackgroundTransparency = 1
	oppHPText.Text = string.format("%d / %d", self.OpponentActiveMonster.CurrentHealth, self.OpponentActiveMonster.MaxHealth)
	oppHPText.TextColor3 = Color3.fromRGB(255, 255, 255)
	oppHPText.Font = Enum.Font.GothamBold
	oppHPText.TextSize = 12
	oppHPText.Parent = oppHPBg
	self.OpponentHPText = oppHPText

	-- 2. Your Status Plate (Bottom Left)
	local yourPlate = Instance.new("Frame")
	yourPlate.Size = UDim2.new(0, 320, 0, 80)
	yourPlate.Position = UDim2.new(0, 30, 1, -240)
	yourPlate.BackgroundColor3 = Color3.fromRGB(25, 35, 30)
	yourPlate.Parent = overlay
	createRoundedCorner(yourPlate, 12)

	local yourName = Instance.new("TextLabel")
	yourName.Size = UDim2.new(1, -20, 0, 26)
	yourName.Position = UDim2.new(0, 10, 0, 8)
	yourName.BackgroundTransparency = 1
	yourName.Text = string.format("%s (Lv. %d)", self.YourActiveMonster.Nickname or self.YourActiveMonster.SpeciesId, self.YourActiveMonster.Level)
	yourName.TextColor3 = Color3.fromRGB(100, 240, 120)
	yourName.Font = Enum.Font.GothamBold
	yourName.TextScaled = true
	yourName.TextXAlignment = Enum.TextXAlignment.Left
	yourName.Parent = yourPlate

	local yourHPBg = Instance.new("Frame")
	yourHPBg.Size = UDim2.new(1, -20, 0, 18)
	yourHPBg.Position = UDim2.new(0, 10, 0, 42)
	yourHPBg.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	yourHPBg.Parent = yourPlate
	createRoundedCorner(yourHPBg, 6)

	local yourHPFill = Instance.new("Frame")
	yourHPFill.Size = UDim2.new(1, 0, 1, 0)
	yourHPFill.BackgroundColor3 = Color3.fromRGB(60, 220, 90)
	yourHPFill.Parent = yourHPBg
	createRoundedCorner(yourHPFill, 6)
	self.YourHPBar = yourHPFill

	local yourHPText = Instance.new("TextLabel")
	yourHPText.Size = UDim2.new(1, 0, 1, 0)
	yourHPText.BackgroundTransparency = 1
	yourHPText.Text = string.format("%d / %d", self.YourActiveMonster.CurrentHealth, self.YourActiveMonster.MaxHealth)
	yourHPText.TextColor3 = Color3.fromRGB(255, 255, 255)
	yourHPText.Font = Enum.Font.GothamBold
	yourHPText.TextSize = 12
	yourHPText.Parent = yourHPBg
	self.YourHPText = yourHPText

	-- 3. Center Battle Log / Prompt
	local logLabel = Instance.new("TextLabel")
	logLabel.Size = UDim2.new(0, 500, 0, 45)
	logLabel.Position = UDim2.new(0.5, -250, 1, -210)
	logLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	logLabel.Text = string.format("Choose an action for %s!", self.YourActiveMonster.Nickname or self.YourActiveMonster.SpeciesId)
	logLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	logLabel.Font = Enum.Font.GothamBold
	logLabel.TextSize = 16
	logLabel.Parent = overlay
	createRoundedCorner(logLabel, 10)
	self.LogLabel = logLabel

	-- 4. Action / Skills Bar (Bottom)
	local skillsContainer = Instance.new("Frame")
	skillsContainer.Size = UDim2.new(0, 600, 0, 80)
	skillsContainer.Position = UDim2.new(0.5, -300, 1, -150)
	skillsContainer.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	skillsContainer.Parent = overlay
	createRoundedCorner(skillsContainer, 14)
	self.SkillsContainer = skillsContainer

	self:_renderSkillButtons()
end

function CombatController:_renderSkillButtons()
	if not self.SkillsContainer or not self.YourActiveMonster then return end
	self.SkillsContainer:ClearAllChildren()

	local skills = self.YourActiveMonster.SkillsEquipped
	local numButtons = #skills + 1 -- Skills + Pass
	local btnWidth = 1 / numButtons

	for i, skillId in ipairs(skills) do
		local skillDef = AttackDefinitions.Get(skillId)
		local btn = Instance.new("TextButton")
		btn.Name = "SkillBtn_" .. skillId
		btn.Size = UDim2.new(btnWidth, -8, 1, -12)
		btn.Position = UDim2.new((i - 1) * btnWidth, 4, 0, 6)
		btn.BackgroundColor3 = Color3.fromRGB(50, 120, 220)
		btn.Text = string.format("%s\n(%s | Pwr %d)", skillDef and skillDef.DisplayName or skillId, skillDef and skillDef.Element or "", skillDef and skillDef.Power or 0)
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 13
		btn.Parent = self.SkillsContainer
		createRoundedCorner(btn, 10)

		btn.MouseButton1Click:Connect(function()
			self:SubmitAction("Skill", skillId)
		end)
	end

	-- Pass Button
	local passBtn = Instance.new("TextButton")
	passBtn.Name = "PassBtn"
	passBtn.Size = UDim2.new(btnWidth, -8, 1, -12)
	passBtn.Position = UDim2.new((numButtons - 1) * btnWidth, 4, 0, 6)
	passBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 130)
	passBtn.Text = "🛡️ Defend / Pass"
	passBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	passBtn.Font = Enum.Font.GothamBold
	passBtn.TextSize = 13
	passBtn.Parent = self.SkillsContainer
	createRoundedCorner(passBtn, 10)

	passBtn.MouseButton1Click:Connect(function()
		self:SubmitAction("Pass", nil)
	end)
end

function CombatController:SubmitAction(actionType: Types.CombatActionType, skillId: string?)
	if not self.IsActive then return end
	if self.LogLabel then
		self.LogLabel.Text = "Waiting for turn resolution..."
	end
	if self.SkillsContainer then
		self.SkillsContainer.Visible = false
	end

	Network.InvokeServer("SubmitBattleAction", {
		Type = actionType,
		SkillId = skillId,
	})
end

function CombatController:OnTurnReport(report: Types.TurnReport)
	for _, action in ipairs(report.Actions) do
		if self.LogLabel then
			local critText = action.IsCritical and " CRITICAL HIT!" or ""
			local elemText = (action.ElementMultiplier > 1.0) and " (Super Effective!)" or ""
			self.LogLabel.Text = string.format("%s used %s! Dealt %d damage!%s%s",
				(action.ActorUUID == self.YourActiveMonster.UUID) and "You" or "Opponent",
				action.SkillName or "Action",
				action.DamageDealt,
				critText,
				elemText
			)
		end

		-- Update HP Bar
		if action.TargetUUID == self.YourActiveMonster.UUID then
			self.YourActiveMonster.CurrentHealth = action.TargetRemainingHealth
			local ratio = math.clamp(self.YourActiveMonster.CurrentHealth / self.YourActiveMonster.MaxHealth, 0, 1)
			if self.YourHPBar then
				TweenService:Create(self.YourHPBar, TweenInfo.new(0.4), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
			end
			if self.YourHPText then
				self.YourHPText.Text = string.format("%d / %d", self.YourActiveMonster.CurrentHealth, self.YourActiveMonster.MaxHealth)
			end
		elseif self.OpponentActiveMonster and action.TargetUUID == self.OpponentActiveMonster.UUID then
			self.OpponentActiveMonster.CurrentHealth = action.TargetRemainingHealth
			local ratio = math.clamp(self.OpponentActiveMonster.CurrentHealth / self.OpponentActiveMonster.MaxHealth, 0, 1)
			if self.OpponentHPBar then
				TweenService:Create(self.OpponentHPBar, TweenInfo.new(0.4), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
			end
			if self.OpponentHPText then
				self.OpponentHPText.Text = string.format("%d / %d", self.OpponentActiveMonster.CurrentHealth, self.OpponentActiveMonster.MaxHealth)
			end
		end

		task.wait(1.4)
	end

	-- Re-enable skills container if battle is still ongoing
	if self.IsActive and not report.WinnerPlayerUserId then
		if self.SkillsContainer then
			self.SkillsContainer.Visible = true
		end
		if self.LogLabel then
			self.LogLabel.Text = string.format("Turn %d: Select your move!", report.TurnNumber + 1)
		end
	end
end

function CombatController:OnBattleEnded(result: any)
	self.IsActive = false
	if self.LogLabel then
		self.LogLabel.Text = result.Victory and "🎉 VICTORY! You won the battle!" or "💀 DEFEAT! Good fight!"
		self.LogLabel.BackgroundColor3 = result.Victory and Color3.fromRGB(50, 180, 80) or Color3.fromRGB(180, 50, 50)
	end

	task.wait(3.5)
	if self.BattleOverlay then
		self.BattleOverlay:Destroy()
		self.BattleOverlay = nil
	end
end

return CombatController
