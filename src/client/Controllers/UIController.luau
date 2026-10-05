--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)
local MonsterDefinitions = require(ReplicatedStorage.Shared.MonsterDefinitions)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

local UIController = {
	ScreenGui = nil :: ScreenGui?,
	HUD = nil :: Frame?,
	CoinLabel = nil :: TextLabel?,
	GemLabel = nil :: TextLabel?,
	LevelLabel = nil :: TextLabel?,
	ActiveModal = nil :: Frame?,
	Modals = {} :: { [string]: Frame },
}

local function createRoundedCorner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function createStroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function UIController:Init()
	Logger:Info("UI", "Initializing UIController...")
	self:_buildScreenGui()
	self:_buildHUD()
	self:_buildBottomNav()
	self:_buildModals()

	-- Network event listeners
	Network.OnClientEvent("PlayerDataLoaded", function(profile: Types.PlayerData)
		self:UpdateHUD(profile.Currency.Coins, profile.Currency.Gems, profile.Progression.Level, profile.Progression.XP)
	end)

	Network.OnClientEvent("PlayerDataUpdated", function(profile: Types.PlayerData)
		self:UpdateHUD(profile.Currency.Coins, profile.Currency.Gems, profile.Progression.Level, profile.Progression.XP)
		self:RefreshActiveModal()
	end)

	Network.OnClientEvent("CurrencyChanged", function(data: any)
		if data.Currency == "Coins" and self.CoinLabel then
			self.CoinLabel.Text = string.format("🪙 %d", data.Total)
		elseif data.Currency == "Gems" and self.GemLabel then
			self.GemLabel.Text = string.format("💎 %d", data.Total)
		end
	end)

	Network.OnClientEvent("MonsterAcquired", function(newMonster: Types.MonsterInstance)
		self:ShowNotification(string.format("New Monster Acquired: %s!", newMonster.Nickname or newMonster.SpeciesId), Color3.fromRGB(80, 230, 120))
	end)

	Network.OnClientEvent("PlotPurchased", function(data: any)
		self:ShowNotification(string.format("Unlocked %s!", data.Name), Color3.fromRGB(100, 200, 255))
	end)

	Network.OnClientEvent("DecorationPlaced", function(data: any)
		self:ShowNotification("Placed decoration on Plot!", Color3.fromRGB(255, 215, 80))
	end)
end

function UIController:Start()
	-- Request initial profile
	task.spawn(function()
		local profile = Network.InvokeServer("GetPlayerData")
		if profile then
			self:UpdateHUD(profile.Currency.Coins, profile.Currency.Gems, profile.Progression.Level, profile.Progression.XP)
		end
	end)
end

function UIController:_buildScreenGui()
	local existing = playerGui:FindFirstChild("MonsterIslandsGui")
	if existing then existing:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "MonsterIslandsGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	self.ScreenGui = gui
end

function UIController:_buildHUD()
	if not self.ScreenGui then return end

	local hud = Instance.new("Frame")
	hud.Name = "TopHUD"
	hud.Size = UDim2.new(0, 480, 0, 50)
	hud.Position = UDim2.new(0.5, -240, 0, 15)
	hud.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	hud.BackgroundTransparency = 0.2
	hud.BorderSizePixel = 0
	hud.Parent = self.ScreenGui
	createRoundedCorner(hud, 12)
	createStroke(hud, Color3.fromRGB(60, 60, 80), 1.5)
	self.HUD = hud

	-- Coins Label
	local coinLabel = Instance.new("TextLabel")
	coinLabel.Name = "Coins"
	coinLabel.Size = UDim2.new(0.33, -10, 1, 0)
	coinLabel.Position = UDim2.new(0, 10, 0, 0)
	coinLabel.BackgroundTransparency = 1
	coinLabel.Text = "🪙 0"
	coinLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	coinLabel.Font = Enum.Font.GothamBold
	coinLabel.TextScaled = true
	coinLabel.Parent = hud
	self.CoinLabel = coinLabel

	-- Gems Label
	local gemLabel = Instance.new("TextLabel")
	gemLabel.Name = "Gems"
	gemLabel.Size = UDim2.new(0.33, -10, 1, 0)
	gemLabel.Position = UDim2.new(0.33, 5, 0, 0)
	gemLabel.BackgroundTransparency = 1
	gemLabel.Text = "💎 0"
	gemLabel.TextColor3 = Color3.fromRGB(80, 220, 255)
	gemLabel.Font = Enum.Font.GothamBold
	gemLabel.TextScaled = true
	gemLabel.Parent = hud
	self.GemLabel = gemLabel

	-- Level Label
	local lvlLabel = Instance.new("TextLabel")
	lvlLabel.Name = "Level"
	lvlLabel.Size = UDim2.new(0.33, -10, 1, 0)
	lvlLabel.Position = UDim2.new(0.66, 5, 0, 0)
	lvlLabel.BackgroundTransparency = 1
	lvlLabel.Text = "⭐ Lv. 1"
	lvlLabel.TextColor3 = Color3.fromRGB(160, 255, 120)
	lvlLabel.Font = Enum.Font.GothamBold
	lvlLabel.TextScaled = true
	lvlLabel.Parent = hud
	self.LevelLabel = lvlLabel
end

function UIController:_buildBottomNav()
	if not self.ScreenGui then return end

	local nav = Instance.new("Frame")
	nav.Name = "BottomNav"
	nav.Size = UDim2.new(0, 440, 0, 54)
	nav.Position = UDim2.new(0.5, -220, 1, -70)
	nav.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	nav.BackgroundTransparency = 0.2
	nav.BorderSizePixel = 0
	nav.Parent = self.ScreenGui
	createRoundedCorner(nav, 14)
	createStroke(nav, Color3.fromRGB(60, 60, 80), 1.5)

	local buttons = {
		{ Id = "Monsters", Text = "🐾 Monsters", Color = Color3.fromRGB(50, 150, 240) },
		{ Id = "Breeding", Text = "🧬 Breeding", Color = Color3.fromRGB(240, 100, 150) },
		{ Id = "Plots", Text = "🏝️ Plots", Color = Color3.fromRGB(70, 190, 80) },
		{ Id = "Arena", Text = "⚔️ PvP Arena", Color = Color3.fromRGB(240, 70, 50) },
	}

	local btnWidth = 1 / #buttons
	for i, btnData in ipairs(buttons) do
		local btn = Instance.new("TextButton")
		btn.Name = "NavBtn_" .. btnData.Id
		btn.Size = UDim2.new(btnWidth, -6, 1, -8)
		btn.Position = UDim2.new((i - 1) * btnWidth, 3, 0, 4)
		btn.BackgroundColor3 = btnData.Color
		btn.Text = btnData.Text
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 14
		btn.Parent = nav
		createRoundedCorner(btn, 10)

		btn.MouseButton1Click:Connect(function()
			self:ToggleModal(btnData.Id)
		end)
	end
end

function UIController:_buildModals()
	if not self.ScreenGui then return end

	local modalNames = { "Monsters", "Breeding", "Plots", "Arena" }
	for _, mName in ipairs(modalNames) do
		local modal = Instance.new("Frame")
		modal.Name = "Modal_" .. mName
		modal.Size = UDim2.new(0, 560, 0, 400)
		modal.Position = UDim2.new(0.5, -280, 0.5, -200)
		modal.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
		modal.BackgroundTransparency = 0.05
		modal.BorderSizePixel = 0
		modal.Visible = false
		modal.Parent = self.ScreenGui
		createRoundedCorner(modal, 16)
		createStroke(modal, Color3.fromRGB(80, 80, 110), 2)

		-- Header
		local header = Instance.new("Frame")
		header.Name = "Header"
		header.Size = UDim2.new(1, 0, 0, 44)
		header.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
		header.BorderSizePixel = 0
		header.Parent = modal
		createRoundedCorner(header, 16)

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, -50, 1, 0)
		title.Position = UDim2.new(0, 15, 0, 0)
		title.BackgroundTransparency = 1
		title.Text = mName .. " Management"
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 18
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = header

		local closeBtn = Instance.new("TextButton")
		closeBtn.Name = "CloseBtn"
		closeBtn.Size = UDim2.new(0, 32, 0, 32)
		closeBtn.Position = UDim2.new(1, -38, 0, 6)
		closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
		closeBtn.Text = "✕"
		closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		closeBtn.Font = Enum.Font.GothamBold
		closeBtn.TextSize = 16
		closeBtn.Parent = header
		createRoundedCorner(closeBtn, 8)
		closeBtn.MouseButton1Click:Connect(function()
			self:CloseModal(mName)
		end)

		-- Content ScrollFrame
		local content = Instance.new("ScrollingFrame")
		content.Name = "Content"
		content.Size = UDim2.new(1, -20, 1, -54)
		content.Position = UDim2.new(0, 10, 0, 48)
		content.BackgroundTransparency = 1
		content.BorderSizePixel = 0
		content.ScrollBarThickness = 6
		content.Parent = modal

		self.Modals[mName] = modal
	end
end

function UIController:ToggleModal(modalName: string)
	local modal = self.Modals[modalName]
	if not modal then return end

	if modal.Visible then
		self:CloseModal(modalName)
	else
		-- Close any other open modal
		for name, m in pairs(self.Modals) do
			if name ~= modalName then m.Visible = false end
		end
		modal.Visible = true
		self.ActiveModal = modal
		self:PopulateModal(modalName)
	end
end

function UIController:CloseModal(modalName: string)
	local modal = self.Modals[modalName]
	if modal then
		modal.Visible = false
		if self.ActiveModal == modal then
			self.ActiveModal = nil
		end
	end
end

function UIController:RefreshActiveModal()
	for name, modal in pairs(self.Modals) do
		if modal.Visible then
			self:PopulateModal(name)
		end
	end
end

function UIController:PopulateModal(modalName: string)
	local modal = self.Modals[modalName]
	if not modal then return end
	local content = modal:FindFirstChild("Content") :: ScrollingFrame
	if not content then return end

	content:ClearAllChildren()

	local profile: Types.PlayerData = Network.InvokeServer("GetPlayerData")
	if not profile then return end

	local uiList = Instance.new("UIListLayout")
	uiList.SortOrder = Enum.SortOrder.LayoutOrder
	uiList.Padding = UDim.new(0, 8)
	uiList.Parent = content

	if modalName == "Monsters" then
		-- List monsters
		local count = 0
		for uuid, monster in pairs(profile.Monsters) do
			count += 1
			local def = MonsterDefinitions.Get(monster.SpeciesId)
			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, -10, 0, 75)
			card.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
			card.Parent = content
			createRoundedCorner(card, 10)
			createStroke(card, Color3.fromRGB(60, 60, 85), 1)

			local info = Instance.new("TextLabel")
			info.Size = UDim2.new(0.65, 0, 1, 0)
			info.Position = UDim2.new(0, 12, 0, 0)
			info.BackgroundTransparency = 1
			info.TextXAlignment = Enum.TextXAlignment.Left
			info.Font = Enum.Font.GothamMedium
			info.TextColor3 = Color3.fromRGB(240, 240, 240)
			info.TextSize = 13
			info.Text = string.format("%s (Lv. %d) - %s\nHP: %d/%d | Atk: %d | Def: %d | Spd: %d\nPlot: %s",
				monster.Nickname or (def and def.DisplayName or monster.SpeciesId),
				monster.Level,
				table.concat(def and def.Elements or {}, "/"),
				monster.CurrentHealth, monster.MaxHealth,
				monster.CalculatedStats.Attack, monster.CalculatedStats.Defense, monster.CalculatedStats.Speed,
				monster.AssignedPlotId and ("Plot " .. tostring(monster.AssignedPlotId)) or "None"
			)
			info.Parent = card

			-- Assign to Plot 1 or Team button
			local assignBtn = Instance.new("TextButton")
			assignBtn.Size = UDim2.new(0.3, -10, 0, 36)
			assignBtn.Position = UDim2.new(0.7, 0, 0.5, -18)
			assignBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 90)
			assignBtn.Text = monster.AssignedPlotId and "Unassign" or "Place Plot 1"
			assignBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			assignBtn.Font = Enum.Font.GothamBold
			assignBtn.TextSize = 13
			assignBtn.Parent = card
			createRoundedCorner(assignBtn, 8)

			assignBtn.MouseButton1Click:Connect(function()
				if monster.AssignedPlotId then
					Network.InvokeServer("PlaceMonsterOnPlot", { PlotId = monster.AssignedPlotId, MonsterUUID = monster.UUID })
				else
					Network.InvokeServer("PlaceMonsterOnPlot", { PlotId = 1, MonsterUUID = monster.UUID })
				end
				task.wait(0.2)
				self:PopulateModal("Monsters")
			end)
		end
		content.CanvasSize = UDim2.new(0, 0, 0, count * 85)

	elseif modalName == "Breeding" then
		-- Breeding interface
		local instructions = Instance.new("TextLabel")
		instructions.Size = UDim2.new(1, -10, 0, 40)
		instructions.BackgroundTransparency = 1
		instructions.Text = "Combine two owned monsters to discover new species and inherit genetic IV stats!"
		instructions.TextColor3 = Color3.fromRGB(220, 220, 240)
		instructions.Font = Enum.Font.Gotham
		instructions.TextSize = 13
		instructions.Parent = content

		-- Check active sessions
		local sessionCount = 0
		for sId, session in pairs(profile.BreedingSessions) do
			if not session.IsHatched then
				sessionCount += 1
				local sFrame = Instance.new("Frame")
				sFrame.Size = UDim2.new(1, -10, 0, 80)
				sFrame.BackgroundColor3 = Color3.fromRGB(45, 35, 55)
				sFrame.Parent = content
				createRoundedCorner(sFrame, 10)

				local now = os.time()
				local ready = now >= session.EggReadyAt
				local timeLeft = math.max(0, session.EggReadyAt - now)

				local sText = Instance.new("TextLabel")
				sText.Size = UDim2.new(0.65, 0, 1, 0)
				sText.Position = UDim2.new(0, 10, 0, 0)
				sText.BackgroundTransparency = 1
				sText.TextColor3 = Color3.fromRGB(255, 220, 150)
				sText.Font = Enum.Font.GothamMedium
				sText.TextSize = 13
				sText.TextXAlignment = Enum.TextXAlignment.Left
				sText.Text = string.format("🥚 Egg Incubating: %s\nStatus: %s",
					session.EggSpeciesId,
					ready and "READY TO HATCH!" or string.format("%ds remaining", timeLeft)
				)
				sText.Parent = sFrame

				local hatchBtn = Instance.new("TextButton")
				hatchBtn.Size = UDim2.new(0.3, -10, 0, 40)
				hatchBtn.Position = UDim2.new(0.7, 0, 0.5, -20)
				hatchBtn.BackgroundColor3 = ready and Color3.fromRGB(240, 180, 50) or Color3.fromRGB(80, 80, 90)
				hatchBtn.Text = ready and "🐣 Hatch!" or "Waiting..."
				hatchBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				hatchBtn.Font = Enum.Font.GothamBold
				hatchBtn.TextSize = 14
				hatchBtn.Parent = sFrame
				createRoundedCorner(hatchBtn, 8)

				if ready then
					hatchBtn.MouseButton1Click:Connect(function()
						local success, err = Network.InvokeServer("ClaimBreedingEgg", sId)
						if success then
							self:ShowNotification("Egg Hatched Successfully!", Color3.fromRGB(80, 230, 120))
							self:PopulateModal("Breeding")
						else
							self:ShowNotification(tostring(err), Color3.fromRGB(255, 80, 80))
						end
					end)
				end
			end
		end

		-- Quick Breed Button if player has at least 2 monsters
		local monsterList = {}
		for _, m in pairs(profile.Monsters) do table.insert(monsterList, m) end

		if #monsterList >= 2 then
			local breedBtn = Instance.new("TextButton")
			breedBtn.Size = UDim2.new(1, -10, 0, 44)
			breedBtn.BackgroundColor3 = Color3.fromRGB(220, 80, 130)
			breedBtn.Text = string.format("🧬 Breed: %s + %s", monsterList[1].Nickname or monsterList[1].SpeciesId, monsterList[2].Nickname or monsterList[2].SpeciesId)
			breedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			breedBtn.Font = Enum.Font.GothamBold
			breedBtn.TextSize = 14
			breedBtn.Parent = content
			createRoundedCorner(breedBtn, 10)

			breedBtn.MouseButton1Click:Connect(function()
				local success, err = Network.InvokeServer("StartBreeding", {
					ParentA_UUID = monsterList[1].UUID,
					ParentB_UUID = monsterList[2].UUID,
				})
				if success then
					self:ShowNotification("Breeding ritual started!", Color3.fromRGB(240, 120, 200))
					self:PopulateModal("Breeding")
				else
					self:ShowNotification(tostring(err), Color3.fromRGB(255, 80, 80))
				end
			end)
		else
			local note = Instance.new("TextLabel")
			note.Size = UDim2.new(1, -10, 0, 40)
			note.BackgroundTransparency = 1
			note.Text = "You need at least 2 monsters to breed. Acquire another one!"
			note.TextColor3 = Color3.fromRGB(255, 180, 100)
			note.Font = Enum.Font.GothamMedium
			note.TextSize = 13
			note.Parent = content
		end

		content.CanvasSize = UDim2.new(0, 0, 0, 300)

	elseif modalName == "Plots" then
		local totalHeight = 0
		for _, plotConfig in ipairs(Config.PLOTS) do
			local pData = profile.Plots[tostring(plotConfig.Id)]
			local isOwned = pData and pData.IsUnlocked

			local card = Instance.new("Frame")
			local cardHeight = isOwned and 220 or 65
			card.Size = UDim2.new(1, -10, 0, cardHeight)
			card.BackgroundColor3 = isOwned and Color3.fromRGB(30, 45, 35) or Color3.fromRGB(40, 40, 50)
			card.Parent = content
			createRoundedCorner(card, 10)
			totalHeight += cardHeight + 10

			local pLabel = Instance.new("TextLabel")
			pLabel.Size = UDim2.new(1, -20, 0, 35)
			pLabel.Position = UDim2.new(0, 10, 0, 5)
			pLabel.BackgroundTransparency = 1
			pLabel.TextXAlignment = Enum.TextXAlignment.Left
			pLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			pLabel.Font = Enum.Font.GothamBold
			pLabel.TextSize = 14
			pLabel.Text = string.format("%s - %s (Monsters: %d/%d)",
				plotConfig.Name,
				isOwned and "UNLOCKED" or string.format("LOCKED (Cost: %d Coins)", plotConfig.CostCoins),
				isOwned and (pData.PlacedMonsters and #pData.PlacedMonsters or 0) or 0,
				plotConfig.MaxMonstersCapacity
			)
			pLabel.Parent = card

			if not isOwned then
				local buyBtn = Instance.new("TextButton")
				buyBtn.Size = UDim2.new(0.3, -10, 0, 36)
				buyBtn.Position = UDim2.new(0.7, 0, 0.5, -18)
				buyBtn.BackgroundColor3 = Color3.fromRGB(70, 180, 90)
				buyBtn.Text = string.format("Unlock (%d)", plotConfig.CostCoins)
				buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				buyBtn.Font = Enum.Font.GothamBold
				buyBtn.TextSize = 13
				buyBtn.Parent = card
				createRoundedCorner(buyBtn, 8)

				buyBtn.MouseButton1Click:Connect(function()
					local success, err = Network.InvokeServer("RequestPurchasePlot", plotConfig.Id)
					if success then
						self:ShowNotification("Plot Unlocked!", Color3.fromRGB(80, 230, 120))
						self:PopulateModal("Plots")
					else
						self:ShowNotification(tostring(err), Color3.fromRGB(255, 80, 80))
					end
				end)
			else
				-- Decoration Catalog bar for this plot
				local decoHeader = Instance.new("TextLabel")
				decoHeader.Size = UDim2.new(1, -20, 0, 20)
				decoHeader.Position = UDim2.new(0, 10, 0, 42)
				decoHeader.BackgroundTransparency = 1
				decoHeader.TextXAlignment = Enum.TextXAlignment.Left
				decoHeader.TextColor3 = Color3.fromRGB(240, 220, 140)
				decoHeader.Font = Enum.Font.GothamMedium
				decoHeader.TextSize = 12
				decoHeader.Text = "🎨 Build & Place Decorations (4-stud grid):"
				decoHeader.Parent = card

				local decoScroll = Instance.new("ScrollingFrame")
				decoScroll.Size = UDim2.new(1, -20, 0, 60)
				decoScroll.Position = UDim2.new(0, 10, 0, 65)
				decoScroll.BackgroundColor3 = Color3.fromRGB(20, 25, 22)
				decoScroll.BorderSizePixel = 0
				decoScroll.CanvasSize = UDim2.new(0, #Config.DECORATIONS * 140, 0, 0)
				decoScroll.ScrollBarThickness = 4
				decoScroll.Parent = card
				createRoundedCorner(decoScroll, 8)

				local dLayout = Instance.new("UIListLayout")
				dLayout.FillDirection = Enum.FillDirection.Horizontal
				dLayout.Padding = UDim.new(0, 6)
				dLayout.Parent = decoScroll

				for _, deco in ipairs(Config.DECORATIONS) do
					local dBtn = Instance.new("TextButton")
					dBtn.Size = UDim2.new(0, 130, 1, -8)
					dBtn.BackgroundColor3 = Color3.fromRGB(50, 80, 60)
					dBtn.Text = string.format("%s\n🪙 %d", deco.Name, deco.CostCoins)
					dBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
					dBtn.Font = Enum.Font.GothamMedium
					dBtn.TextSize = 11
					dBtn.Parent = decoScroll
					createRoundedCorner(dBtn, 6)

					dBtn.MouseButton1Click:Connect(function()
						local randX = math.random(-2, 2) * (Config.PLOT_GRID_SIZE or 4)
						local randZ = math.random(-2, 2) * (Config.PLOT_GRID_SIZE or 4)
						local success, res = Network.InvokeServer("PlacePlotDecoration", {
							PlotId = plotConfig.Id,
							DecorationId = deco.Id,
							LocalX = randX,
							LocalZ = randZ,
							RotationY = 0,
						})
						if success then
							self:ShowNotification(string.format("Placed %s!", deco.Name), Color3.fromRGB(100, 230, 120))
							self:PopulateModal("Plots")
						else
							self:ShowNotification(tostring(res), Color3.fromRGB(255, 80, 80))
						end
					end)
				end

				-- Placed decorations summary & removal
				local placedDecos = pData.PlacedDecorations or {}
				local summaryLabel = Instance.new("TextLabel")
				summaryLabel.Size = UDim2.new(1, -20, 0, 20)
				summaryLabel.Position = UDim2.new(0, 10, 0, 130)
				summaryLabel.BackgroundTransparency = 1
				summaryLabel.TextXAlignment = Enum.TextXAlignment.Left
				summaryLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
				summaryLabel.Font = Enum.Font.GothamMedium
				summaryLabel.TextSize = 12
				summaryLabel.Text = string.format("Placed Items (%d):", #placedDecos)
				summaryLabel.Parent = card

				local placedScroll = Instance.new("ScrollingFrame")
				placedScroll.Size = UDim2.new(1, -20, 0, 55)
				placedScroll.Position = UDim2.new(0, 10, 0, 155)
				placedScroll.BackgroundColor3 = Color3.fromRGB(20, 25, 22)
				placedScroll.BorderSizePixel = 0
				placedScroll.CanvasSize = UDim2.new(0, math.max(1, #placedDecos) * 150, 0, 0)
				placedScroll.ScrollBarThickness = 4
				placedScroll.Parent = card
				createRoundedCorner(placedScroll, 8)

				local pLayout = Instance.new("UIListLayout")
				pLayout.FillDirection = Enum.FillDirection.Horizontal
				pLayout.Padding = UDim.new(0, 6)
				pLayout.Parent = placedScroll

				if #placedDecos == 0 then
					local empty = Instance.new("TextLabel")
					empty.Size = UDim2.new(1, 0, 1, 0)
					empty.BackgroundTransparency = 1
					empty.Text = "No decorations placed yet. Choose one above!"
					empty.TextColor3 = Color3.fromRGB(140, 140, 140)
					empty.Font = Enum.Font.Gotham
					empty.TextSize = 11
					empty.Parent = placedScroll
				else
					for _, placed in ipairs(placedDecos) do
						local pItemBtn = Instance.new("TextButton")
						pItemBtn.Size = UDim2.new(0, 140, 1, -8)
						pItemBtn.BackgroundColor3 = Color3.fromRGB(70, 40, 40)
						pItemBtn.Text = string.format("%s\n🗑️ Remove", placed.DecorationId)
						pItemBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
						pItemBtn.Font = Enum.Font.GothamMedium
						pItemBtn.TextSize = 11
						pItemBtn.Parent = placedScroll
						createRoundedCorner(pItemBtn, 6)

						pItemBtn.MouseButton1Click:Connect(function()
							local success, err = Network.InvokeServer("RemovePlotDecoration", {
								PlotId = plotConfig.Id,
								DecorationUUID = placed.UUID,
							})
							if success then
								self:ShowNotification("Decoration removed", Color3.fromRGB(255, 180, 80))
								self:PopulateModal("Plots")
							else
								self:ShowNotification(tostring(err), Color3.fromRGB(255, 80, 80))
							end
						end)
					end
				end
			end
		end
		content.CanvasSize = UDim2.new(0, 0, 0, totalHeight + 40)

	elseif modalName == "Arena" then
		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(1, -10, 0, 45)
		desc.BackgroundTransparency = 1
		desc.Text = "Challenge other players in 1v1 turn-based battle or train against an AI combatant!"
		desc.TextColor3 = Color3.fromRGB(240, 240, 255)
		desc.Font = Enum.Font.Gotham
		desc.TextSize = 14
		desc.Parent = content

		-- Practice Bot Battle
		local botBtn = Instance.new("TextButton")
		botBtn.Size = UDim2.new(1, -10, 0, 50)
		botBtn.BackgroundColor3 = Color3.fromRGB(70, 130, 230)
		botBtn.Text = "🤖 Practice Battle vs AI Bot"
		botBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		botBtn.Font = Enum.Font.GothamBold
		botBtn.TextSize = 15
		botBtn.Parent = content
		createRoundedCorner(botBtn, 10)

		botBtn.MouseButton1Click:Connect(function()
			self:CloseModal("Arena")
			local success, err = Network.InvokeServer("StartBotBattle")
			if not success then
				self:ShowNotification(tostring(err), Color3.fromRGB(255, 80, 80))
			end
		end)

		-- Matchmaking 1v1 PvP
		local pvpBtn = Instance.new("TextButton")
		pvpBtn.Size = UDim2.new(1, -10, 0, 50)
		pvpBtn.BackgroundColor3 = Color3.fromRGB(230, 70, 60)
		pvpBtn.Text = "⚔️ Find 1v1 PvP Opponent (Queue)"
		pvpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		pvpBtn.Font = Enum.Font.GothamBold
		pvpBtn.TextSize = 15
		pvpBtn.Parent = content
		createRoundedCorner(pvpBtn, 10)

		pvpBtn.MouseButton1Click:Connect(function()
			local success, err = Network.InvokeServer("JoinPvPQueue")
			if success then
				self:ShowNotification("Joined PvP Queue. Waiting for opponent...", Color3.fromRGB(255, 200, 80))
				self:CloseModal("Arena")
			else
				self:ShowNotification(tostring(err), Color3.fromRGB(255, 80, 80))
			end
		end)
	end
end

function UIController:UpdateHUD(coins: number, gems: number, level: number, xp: number)
	if self.CoinLabel then self.CoinLabel.Text = string.format("🪙 %d", coins) end
	if self.GemLabel then self.GemLabel.Text = string.format("💎 %d", gems) end
	if self.LevelLabel then self.LevelLabel.Text = string.format("⭐ Lv. %d", level) end
end

function UIController:ShowNotification(text: string, color: Color3?)
	if not self.ScreenGui then return end

	local notif = Instance.new("TextLabel")
	notif.Size = UDim2.new(0, 360, 0, 42)
	notif.Position = UDim2.new(0.5, -180, 0, 75)
	notif.BackgroundColor3 = color or Color3.fromRGB(50, 50, 70)
	notif.Text = text
	notif.TextColor3 = Color3.fromRGB(255, 255, 255)
	notif.Font = Enum.Font.GothamBold
	notif.TextSize = 14
	notif.Parent = self.ScreenGui
	createRoundedCorner(notif, 10)

	task.spawn(function()
		task.wait(2.5)
		local tween = TweenService:Create(notif, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		notif:Destroy()
	end)
end

return UIController
