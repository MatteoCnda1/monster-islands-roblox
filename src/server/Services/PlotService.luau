--!strict
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)
local PlotMath = require(ReplicatedStorage.Shared.PlotMath)

local PlayerDataService: any = nil
local EconomyService: any = nil
local MonsterService: any = nil

local plotsFolder: Folder
local physicalPlotModels: { [number]: Model } = {}
local physicalDecorationModels: { [string]: Model } = {} -- Keyed by DecorationUUID

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

	-- Handle decoration placement request
	Network.HandleFunction("PlacePlotDecoration", function(player: Player, payload: any)
		if typeof(payload) ~= "table" or typeof(payload.PlotId) ~= "number" or typeof(payload.DecorationId) ~= "string" or typeof(payload.LocalX) ~= "number" or typeof(payload.LocalZ) ~= "number" then
			return false, "Invalid decoration payload"
		end
		return self:PlaceDecoration(player, payload.PlotId, payload.DecorationId, payload.LocalX, payload.LocalZ, payload.RotationY or 0)
	end)

	-- Handle decoration removal
	Network.HandleFunction("RemovePlotDecoration", function(player: Player, payload: any)
		if typeof(payload) ~= "table" or typeof(payload.PlotId) ~= "number" or typeof(payload.DecorationUUID) ~= "string" then
			return false, "Invalid decoration removal payload"
		end
		return self:RemoveDecoration(player, payload.PlotId, payload.DecorationUUID)
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
		self:RenderPlayerDecorations(player)
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
			PlacedDecorations = {},
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

function PlotService:GetDecorationConfig(decorationId: string): Types.DecorationConfig?
	for _, deco in ipairs(Config.DECORATIONS) do
		if deco.Id == decorationId then
			return deco
		end
	end
	return nil
end

local function buildProceduralDecorationModel(config: Types.DecorationConfig, worldPosition: Vector3, rotationY: number): Model
	local model = Instance.new("Model")
	model.Name = "Deco_" .. config.Id

	if config.Id == "Fence_Wood" then
		local post1 = Instance.new("Part")
		post1.Size = Vector3.new(0.6, 3.2, 0.6)
		post1.Position = worldPosition + Vector3.new(-1.8, 1.6, 0)
		post1.Color = config.SecondaryColor
		post1.Material = Enum.Material.Wood
		post1.Anchored = true
		post1.Parent = model

		local post2 = Instance.new("Part")
		post2.Size = Vector3.new(0.6, 3.2, 0.6)
		post2.Position = worldPosition + Vector3.new(1.8, 1.6, 0)
		post2.Color = config.SecondaryColor
		post2.Material = Enum.Material.Wood
		post2.Anchored = true
		post2.Parent = model

		local rail1 = Instance.new("Part")
		rail1.Size = Vector3.new(3.8, 0.4, 0.3)
		rail1.Position = worldPosition + Vector3.new(0, 1.0, 0)
		rail1.Color = config.PrimaryColor
		rail1.Material = Enum.Material.WoodPlanks
		rail1.Anchored = true
		rail1.Parent = model

		local rail2 = Instance.new("Part")
		rail2.Size = Vector3.new(3.8, 0.4, 0.3)
		rail2.Position = worldPosition + Vector3.new(0, 2.2, 0)
		rail2.Color = config.PrimaryColor
		rail2.Material = Enum.Material.WoodPlanks
		rail2.Anchored = true
		rail2.Parent = model

		model.PrimaryPart = post1

	elseif config.Id == "Lantern_Pillar" then
		local base = Instance.new("Part")
		base.Size = Vector3.new(1.8, 4.5, 1.8)
		base.Position = worldPosition + Vector3.new(0, 2.25, 0)
		base.Color = config.PrimaryColor
		base.Material = Enum.Material.Slate
		base.Anchored = true
		base.Parent = model

		local lantern = Instance.new("Part")
		lantern.Size = Vector3.new(1.2, 1.5, 1.2)
		lantern.Position = worldPosition + Vector3.new(0, 5.0, 0)
		lantern.Color = config.SecondaryColor
		lantern.Material = Enum.Material.Neon
		lantern.Anchored = true
		lantern.Parent = model

		local light = Instance.new("PointLight")
		light.Color = config.SecondaryColor
		light.Brightness = 2.5
		light.Range = 16
		light.Parent = lantern

		model.PrimaryPart = base

	elseif config.Id == "Elemental_Flower" then
		local stem = Instance.new("Part")
		stem.Size = Vector3.new(0.4, 1.6, 0.4)
		stem.Position = worldPosition + Vector3.new(0, 0.8, 0)
		stem.Color = config.SecondaryColor
		stem.Material = Enum.Material.Grass
		stem.Anchored = true
		stem.Parent = model

		local blossom = Instance.new("Part")
		blossom.Size = Vector3.new(2.4, 0.6, 2.4)
		blossom.Position = worldPosition + Vector3.new(0, 1.8, 0)
		blossom.Color = config.PrimaryColor
		blossom.Material = Enum.Material.Neon
		blossom.Anchored = true
		blossom.Parent = model

		model.PrimaryPart = stem

	elseif config.Id == "Stone_Bench" then
		local seat = Instance.new("Part")
		seat.Size = Vector3.new(4, 0.5, 1.8)
		seat.Position = worldPosition + Vector3.new(0, 1.4, 0)
		seat.Color = config.PrimaryColor
		seat.Material = Enum.Material.Cobblestone
		seat.Anchored = true
		seat.Parent = model

		for _, mult in ipairs({ -1.5, 1.5 }) do
			local leg = Instance.new("Part")
			leg.Size = Vector3.new(0.6, 1.4, 1.6)
			leg.Position = worldPosition + Vector3.new(mult * 1.5, 0.7, 0)
			leg.Color = config.SecondaryColor
			leg.Material = Enum.Material.Slate
			leg.Anchored = true
			leg.Parent = model
		end

		model.PrimaryPart = seat

	elseif config.Id == "Training_Dummy" then
		local stand = Instance.new("Part")
		stand.Size = Vector3.new(0.6, 3.5, 0.6)
		stand.Position = worldPosition + Vector3.new(0, 1.75, 0)
		stand.Color = Color3.fromRGB(90, 60, 30)
		stand.Material = Enum.Material.Wood
		stand.Anchored = true
		stand.Parent = model

		local torso = Instance.new("Part")
		torso.Size = Vector3.new(2.2, 2.8, 1.2)
		torso.Position = worldPosition + Vector3.new(0, 3.2, 0)
		torso.Color = config.PrimaryColor
		torso.Material = Enum.Material.Fabric
		torso.Anchored = true
		torso.Parent = model

		local target = Instance.new("Part")
		target.Size = Vector3.new(1.0, 1.0, 0.2)
		target.Position = torso.Position + Vector3.new(0, 0, -0.65)
		target.Color = config.SecondaryColor
		target.Material = Enum.Material.Neon
		target.Anchored = true
		target.Parent = model

		model.PrimaryPart = stand
	end

	return model
end

function PlotService:PlaceDecoration(
	player: Player,
	plotId: number,
	decorationId: string,
	localX: number,
	localZ: number,
	rotationY: number
): (boolean, any)
	local plotConfig = self:GetPlotConfig(plotId)
	if not plotConfig then return false, "Plot does not exist" end

	local decoConfig = self:GetDecorationConfig(decorationId)
	if not decoConfig then return false, "Decoration does not exist" end

	local profile = PlayerDataService:GetProfile(player)
	if not profile then return false, "No player profile" end

	local plotKey = tostring(plotId)
	local plotData = profile.Plots[plotKey]
	if not plotData or not plotData.IsUnlocked then
		return false, "Plot is locked"
	end

	-- Grid snapping to Config.PLOT_GRID_SIZE, clamped within plot dimensions
	local snappedX, snappedZ = PlotMath.SnapDecorationPosition(localX, localZ, plotConfig.Size)

	-- Check coins and deduct
	if decoConfig.CostCoins > 0 then
		local deducted = EconomyService:DeductCoins(player, decoConfig.CostCoins, "Place Deco: " .. decoConfig.Name)
		if not deducted then
			return false, "Not enough Coins"
		end
	end

	local decoUUID = HttpService:GenerateGUID(false)
	local placedDeco: Types.PlacedDecoration = {
		UUID = decoUUID,
		DecorationId = decorationId,
		PositionX = snappedX,
		PositionY = (plotConfig.Size.Y / 2),
		PositionZ = snappedZ,
		RotationY = rotationY,
		PlacedAt = os.time(),
	}

	PlayerDataService:UpdateProfile(player, function(prof)
		local p = prof.Plots[plotKey]
		if not p.PlacedDecorations then p.PlacedDecorations = {} end
		table.insert(p.PlacedDecorations, placedDeco)
	end)

	-- Spawn physical model in workspace
	local worldPos = plotConfig.WorldPosition + Vector3.new(snappedX, (plotConfig.Size.Y / 2), snappedZ)
	local model = buildProceduralDecorationModel(decoConfig, worldPos, rotationY)
	model.Parent = plotsFolder
	physicalDecorationModels[decoUUID] = model

	Logger:Info("PLOT", "Player %s placed %s on Plot %d at (%d, %d)", player.Name, decoConfig.Name, plotId, snappedX, snappedZ)
	Network.FireClient("DecorationPlaced", player, { PlotId = plotId, Decoration = placedDeco })
	return true, placedDeco
end

function PlotService:RemoveDecoration(player: Player, plotId: number, decorationUUID: string): (boolean, string?)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then return false, "No player profile" end

	local plotKey = tostring(plotId)
	local plotData = profile.Plots[plotKey]
	if not plotData or not plotData.PlacedDecorations then return false, "No decorations on plot" end

	local foundIdx: number? = nil
	for idx, deco in ipairs(plotData.PlacedDecorations) do
		if deco.UUID == decorationUUID then
			foundIdx = idx
			break
		end
	end

	if not foundIdx then
		return false, "Decoration not found"
	end

	PlayerDataService:UpdateProfile(player, function(prof)
		local p = prof.Plots[plotKey]
		if p and p.PlacedDecorations then
			table.remove(p.PlacedDecorations, foundIdx)
		end
	end)

	-- Destroy 3D model
	local model = physicalDecorationModels[decorationUUID]
	if model then
		model:Destroy()
		physicalDecorationModels[decorationUUID] = nil
	end

	Logger:Info("PLOT", "Player %s removed decoration %s from Plot %d", player.Name, decorationUUID, plotId)
	return true, nil
end

function PlotService:RenderPlayerDecorations(player: Player)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then return end

	for plotKey, plotData in pairs(profile.Plots) do
		local plotId = tonumber(plotKey) or plotData.Id
		local plotConfig = self:GetPlotConfig(plotId)
		if plotConfig and plotData.PlacedDecorations then
			for _, placedDeco in ipairs(plotData.PlacedDecorations) do
				if not physicalDecorationModels[placedDeco.UUID] then
					local decoConfig = self:GetDecorationConfig(placedDeco.DecorationId)
					if decoConfig then
						local worldPos = plotConfig.WorldPosition + Vector3.new(placedDeco.PositionX, placedDeco.PositionY, placedDeco.PositionZ)
						local model = buildProceduralDecorationModel(decoConfig, worldPos, placedDeco.RotationY or 0)
						model.Parent = plotsFolder
						physicalDecorationModels[placedDeco.UUID] = model
					end
				end
			end
		end
	end
end

return PlotService
