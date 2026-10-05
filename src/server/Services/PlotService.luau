--!strict
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)

local PlayerDataService: any = nil
local EconomyService: any = nil
local MonsterService: any = nil

local plotsFolder: Folder
local physicalPlotModels: { [number]: Model } = {}

local PlotService = {}

local function createPhysicalPlotsFolder(): Folder
	local folder = Workspace:FindFirstChild("Plots") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Plots"
		folder.Parent = Workspace
	end
	return folder
end

local function spawnPlotGeometry(plotConfig: Types.PlotConfig): Model
	local plotModel = Instance.new("Model")
	plotModel.Name = "Plot_" .. tostring(plotConfig.Id)

	-- Base ground pad
	local basePad = Instance.new("Part")
	basePad.Name = "BasePad"
	basePad.Size = plotConfig.Size
	basePad.Position = plotConfig.WorldPosition
	basePad.Anchored = true
	basePad.Material = Enum.Material.Grass
	basePad.Color = Color3.fromRGB(80, 160, 75)
	basePad.TopSurface = Enum.SurfaceType.Smooth
	basePad.BottomSurface = Enum.SurfaceType.Smooth
	basePad.Parent = plotModel

	plotModel.PrimaryPart = basePad

	-- Decorative boundary stone border
	local halfX = plotConfig.Size.X / 2
	local halfZ = plotConfig.Size.Z / 2
	local cornerOffsets = {
		Vector3.new(halfX, 1, halfZ),
		Vector3.new(-halfX, 1, halfZ),
		Vector3.new(halfX, 1, -halfZ),
		Vector3.new(-halfX, 1, -halfZ),
	}

	for i, offset in ipairs(cornerOffsets) do
		local pillar = Instance.new("Part")
		pillar.Name = "Pillar_" .. tostring(i)
		pillar.Size = Vector3.new(2, 4, 2)
		pillar.Position = plotConfig.WorldPosition + offset
		pillar.Anchored = true
		pillar.Material = Enum.Material.Slate
		pillar.Color = Color3.fromRGB(120, 120, 130)
		pillar.Parent = plotModel
	end

	-- Center interaction / info podium
	local podium = Instance.new("Part")
	podium.Name = "SignPodium"
	podium.Size = Vector3.new(3, 3, 3)
	podium.Position = plotConfig.WorldPosition + Vector3.new(0, (plotConfig.Size.Y / 2) + 1.5, -halfZ + 3)
	podium.Anchored = true
	podium.Material = Enum.Material.WoodPlanks
	podium.Color = Color3.fromRGB(140, 90, 50)
	podium.Parent = plotModel

	-- Billboard GUI for status display
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PlotBillboard"
	billboard.Size = UDim2.new(0, 200, 0, 80)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 75
	billboard.Parent = podium

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0.45, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = plotConfig.Name
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = billboard

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0.45, 0)
	statusLabel.Position = UDim2.new(0, 0, 0.5, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Locked"
	statusLabel.TextColor3 = Color3.fromRGB(240, 200, 60)
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.Parent = billboard

	-- Proximity Prompt for interaction/purchase
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlotPrompt"
	prompt.ActionText = "Unlock Plot"
	prompt.ObjectText = plotConfig.Name
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.Parent = podium

	plotModel.Parent = plotsFolder
	return plotModel
end

function PlotService:Init()
	Logger:Info("PLOT", "Initializing PlotService...")
	PlayerDataService = require(script.Parent.PlayerDataService)
	EconomyService = require(script.Parent.EconomyService)
	MonsterService = require(script.Parent.MonsterService)

	plotsFolder = createPhysicalPlotsFolder()

	-- Generate physical geometry for all configured plots
	for _, plotConfig in ipairs(Config.PLOTS) do
		local model = spawnPlotGeometry(plotConfig)
		physicalPlotModels[plotConfig.Id] = model
	end

	-- Handle purchase request via network
	Network.HandleFunction("RequestPurchasePlot", function(player: Player, plotId: any)
		if typeof(plotId) ~= "number" then
			return false, "Invalid Plot ID"
		end
		return self:PurchasePlot(player, math.floor(plotId))
	end)

	-- Handle monster placement request
	Network.HandleFunction("PlaceMonsterOnPlot", function(player: Player, payload: any)
		if typeof(payload) ~= "table" or typeof(payload.PlotId) ~= "number" or typeof(payload.MonsterUUID) ~= "string" then
			return false, "Invalid placement parameters"
		end
		return self:PlaceMonster(player, payload.PlotId, payload.MonsterUUID)
	end)
end

function PlotService:Start()
	-- Connect proximity prompts
	for plotId, model in pairs(physicalPlotModels) do
		local podium = model:FindFirstChild("SignPodium")
		if podium then
			local prompt = podium:FindFirstChild("PlotPrompt") :: ProximityPrompt
			if prompt then
				prompt.Triggered:Connect(function(player)
					local success, err = self:PurchasePlot(player, plotId)
					if not success and err then
						Logger:Info("PLOT", "Prompt purchase attempt by %s for Plot %d failed: %s", player.Name, plotId, err)
					end
				end)
			end
		end
	end

	-- Listen for profile loads to refresh plot appearance
	Network.HandleEvent("RefreshPlotsRequest", function(player: Player)
		self:UpdateClientPlotVisuals(player)
	end)
end

function PlotService:GetPlotConfig(plotId: number): Types.PlotConfig?
	for _, config in ipairs(Config.PLOTS) do
		if config.Id == plotId then
			return config
		end
	end
	return nil
end

function PlotService:PurchasePlot(player: Player, plotId: number): (boolean, string?)
	local plotConfig = self:GetPlotConfig(plotId)
	if not plotConfig then
		return false, "Plot does not exist"
	end

	local profile = PlayerDataService:GetProfile(player)
	if not profile then
		return false, "Player data not loaded"
	end

	local plotKey = tostring(plotId)
	local plotData = profile.Plots[plotKey]
	if plotData and plotData.IsUnlocked then
		return false, "Plot is already unlocked"
	end

	-- Check level requirement
	if profile.Progression.Level < plotConfig.RequiredLevel then
		return false, string.format("Level %d required to unlock this plot", plotConfig.RequiredLevel)
	end

	-- Check currency and deduct
	if plotConfig.CostCoins > 0 then
		if not EconomyService:DeductCoins(player, plotConfig.CostCoins, "Purchase Plot " .. tostring(plotId)) then
			return false, "Not enough Coins"
		end
	end

	if plotConfig.CostGems > 0 then
		if not EconomyService:DeductGems(player, plotConfig.CostGems, "Purchase Plot " .. tostring(plotId)) then
			-- Refund coins if gem deduction failed
			if plotConfig.CostCoins > 0 then
				EconomyService:AddCoins(player, plotConfig.CostCoins, "Refund Plot Purchase")
			end
			return false, "Not enough Gems"
		end
	end

	-- Update profile
	local updateSuccess = PlayerDataService:UpdateProfile(player, function(prof)
		prof.Plots[plotKey] = {
			Id = plotId,
			IsUnlocked = true,
			UnlockedAt = os.time(),
			PlacedMonsters = {},
		}
	end)

	if not updateSuccess then
		return false, "Failed to persist plot purchase"
	end

	Logger:Info("PLOT", "Player %s successfully purchased plot %d (%s)", player.Name, plotId, plotConfig.Name)
	self:UpdateClientPlotVisuals(player)
	Network.FireClient("PlotPurchased", player, { PlotId = plotId, Name = plotConfig.Name })

	return true, nil
end

function PlotService:PlaceMonster(player: Player, plotId: number, monsterUUID: string): (boolean, string?)
	local plotConfig = self:GetPlotConfig(plotId)
	if not plotConfig then return false, "Invalid Plot" end

	local profile = PlayerDataService:GetProfile(player)
	if not profile then return false, "No Profile" end

	local plotKey = tostring(plotId)
	local plotData = profile.Plots[plotKey]
	if not plotData or not plotData.IsUnlocked then
		return false, "Plot is locked"
	end

	local monster = profile.Monsters[monsterUUID]
	if not monster then
		return false, "Monster not owned"
	end

	if #plotData.PlacedMonsters >= plotConfig.MaxMonstersCapacity then
		return false, "Plot monster capacity reached"
	end

	-- If monster was assigned to another plot, remove it first
	if monster.AssignedPlotId and monster.AssignedPlotId ~= plotId then
		self:RemoveMonster(player, monsterUUID)
	end

	PlayerDataService:UpdateProfile(player, function(prof)
		prof.Monsters[monsterUUID].AssignedPlotId = plotId
		local currentPlot = prof.Plots[plotKey]
		if not table.find(currentPlot.PlacedMonsters, monsterUUID) then
			table.insert(currentPlot.PlacedMonsters, monsterUUID)
		end
	end)

	-- Spawn or reposition 3D monster on the plot
	MonsterService:RenderMonsterOnPlot(player, monsterUUID, plotId)

	Logger:Info("PLOT", "Player %s assigned monster %s to plot %d", player.Name, monster.SpeciesId, plotId)
	return true, nil
end

function PlotService:RemoveMonster(player: Player, monsterUUID: string): boolean
	local profile = PlayerDataService:GetProfile(player)
	if not profile then return false end

	local monster = profile.Monsters[monsterUUID]
	if not monster or not monster.AssignedPlotId then return false end

	local prevPlotKey = tostring(monster.AssignedPlotId)
	PlayerDataService:UpdateProfile(player, function(prof)
		prof.Monsters[monsterUUID].AssignedPlotId = nil
		local prevPlot = prof.Plots[prevPlotKey]
		if prevPlot then
			local idx = table.find(prevPlot.PlacedMonsters, monsterUUID)
			if idx then
				table.remove(prevPlot.PlacedMonsters, idx)
			end
		end
	end)

	MonsterService:UnrenderMonsterFromPlot(player, monsterUUID)
	return true
end

function PlotService:UpdateClientPlotVisuals(player: Player)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then return end

	for plotId, model in pairs(physicalPlotModels) do
		local plotKey = tostring(plotId)
		local plotData = profile.Plots[plotKey]
		local isUnlocked = plotData and plotData.IsUnlocked
		local config = self:GetPlotConfig(plotId)
		if not config then continue end

		local podium = model:FindFirstChild("SignPodium")
		if podium then
			local billboard = podium:FindFirstChild("PlotBillboard") :: BillboardGui
			local prompt = podium:FindFirstChild("PlotPrompt") :: ProximityPrompt

			if billboard then
				local statusLabel = billboard:FindFirstChild("StatusLabel") :: TextLabel
				if statusLabel then
					if isUnlocked then
						statusLabel.Text = "OWNED"
						statusLabel.TextColor3 = Color3.fromRGB(100, 255, 120)
					else
						statusLabel.Text = string.format("%d Coins", config.CostCoins)
						statusLabel.TextColor3 = Color3.fromRGB(255, 215, 60)
					end
				end
			end

			if prompt then
				prompt.Enabled = not isUnlocked
				if not isUnlocked then
					prompt.ActionText = string.format("Unlock (%d Coins)", config.CostCoins)
				end
			end
		end

		-- Visual ground tint
		local basePad = model:FindFirstChild("BasePad") :: Part
		if basePad then
			basePad.Color = isUnlocked and Color3.fromRGB(90, 180, 85) or Color3.fromRGB(70, 120, 70)
		end
	end
end

return PlotService
