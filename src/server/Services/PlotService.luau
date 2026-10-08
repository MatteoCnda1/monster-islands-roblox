--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)
local PlotSlots = require(ReplicatedStorage.Shared.PlotSlots)

local PlayerDataService: any = nil
local EconomyService: any = nil
local MonsterService: any = nil

local PROFILE_WAIT_TIMEOUT_SECONDS = 30
local OWNER_SIGN_LOCAL_POSITION = Vector3.new(-12, 2, 19)

-- One island slot per player (issue #21). Everything built for a player lives in `Folder`
-- (Workspace.Plots.Slot_<n>) and is destroyed when the slot is released.
type PlayerSlot = {
	Index: number,
	Owner: Player,
	Folder: Folder,
	DecorationsFolder: Folder,
	PlotModels: { [number]: Model }, -- Keyed by PlotId
	DecorationModels: { [string]: Model }, -- Keyed by DecorationUUID
}

local plotsFolder: Folder
local slotsByIndex: { [number]: PlayerSlot } = {}
local slotsByPlayer: { [Player]: PlayerSlot } = {}

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

local function spawnPlotGeometry(plotConfig: Types.PlotConfig, worldPosition: Vector3, parent: Instance): Model
	local plotModel = Instance.new("Model")
	plotModel.Name = "Plot_" .. tostring(plotConfig.Id)
	plotModel:SetAttribute("PlotId", plotConfig.Id)
	plotModel:SetAttribute("IsUnlocked", false)

	-- Base ground pad
	local basePad = Instance.new("Part")
	basePad.Name = "BasePad"
	basePad.Size = plotConfig.Size
	basePad.Position = worldPosition
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
		pillar.Position = worldPosition + offset
		pillar.Anchored = true
		pillar.Material = Enum.Material.Slate
		pillar.Color = Color3.fromRGB(120, 120, 130)
		pillar.Parent = plotModel
	end

	-- Center interaction / info podium
	local podium = Instance.new("Part")
	podium.Name = "SignPodium"
	podium.Size = Vector3.new(3, 3, 3)
	podium.Position = worldPosition + Vector3.new(0, (plotConfig.Size.Y / 2) + 1.5, -halfZ + 3)
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

	-- No ProximityPrompt here: the purchase prompt is created client-side by PlotController,
	-- only on the local player's own plots, and goes through the "RequestPurchasePlot" remote.

	plotModel.Parent = parent
	return plotModel
end

local function spawnOwnerSign(slotIndex: number, owner: Player, parent: Instance)
	local post = Instance.new("Part")
	post.Name = "OwnerSign"
	post.Size = Vector3.new(1.5, 8, 1.5)
	post.Position = PlotSlots.ToWorldPosition(slotIndex, OWNER_SIGN_LOCAL_POSITION) + Vector3.new(0, 4, 0)
	post.Anchored = true
	post.Material = Enum.Material.Wood
	post.Color = Color3.fromRGB(110, 75, 40)
	post.Parent = parent

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OwnerBillboard"
	billboard.Size = UDim2.new(0, 240, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 200
	billboard.Parent = post

	local label = Instance.new("TextLabel")
	label.Name = "OwnerLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = string.format("%s's Island", owner.DisplayName)
	label.TextColor3 = Color3.fromRGB(255, 230, 120)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard
end

-- Yields until the player's profile is loaded (DataStore read can be slow) or the player leaves
local function waitForProfile(player: Player): Types.PlayerData?
	local deadline = os.clock() + PROFILE_WAIT_TIMEOUT_SECONDS
	while player.Parent == Players and os.clock() < deadline do
		local profile = PlayerDataService:GetProfile(player)
		if profile then
			return profile
		end
		task.wait(0.25)
	end
	return nil
end

local function teleportToIsland(player: Player, slot: PlayerSlot, character: Model)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart or slotsByPlayer[player] ~= slot then return end
	task.wait() -- Let the default spawn placement happen first

	local target = PlotSlots.ToWorldPosition(slot.Index, Config.PLOT_SLOTS.SPAWN_LOCAL_POSITION)
	pcall(function()
		player:RequestStreamAroundAsync(target, 5)
	end)
	if character.Parent and slotsByPlayer[player] == slot then
		character:PivotTo(CFrame.new(target))
	end
end

function PlotService:Init()
	Logger:Info("PLOT", "Initializing PlotService...")
	PlayerDataService = require(script.Parent.PlayerDataService)
	EconomyService = require(script.Parent.EconomyService)
	MonsterService = require(script.Parent.MonsterService)

	plotsFolder = createPhysicalPlotsFolder()

	if Players.MaxPlayers > PlotSlots.GetSlotCount() then
		Logger:Warn("PLOT", "Max Players (%d) exceeds island slots (%d): extra players will wait for a free island", Players.MaxPlayers, PlotSlots.GetSlotCount())
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
	-- Per-player islands: assigned on join, released (and handed to a waiting player) on leave
	Players.PlayerAdded:Connect(function(player)
		self:AssignSlot(player, true)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:ReleaseSlot(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:AssignSlot(player, true)
	end

	-- Client refresh request (idempotent: the server also refreshes once the profile is loaded)
	Network.HandleEvent("RefreshPlotsRequest", function(player: Player)
		self:UpdateClientPlotVisuals(player)
		self:RenderPlayerDecorations(player)
	end)
end

-- Gives the player a free island slot and builds their plots on it. Returns the slot index,
-- or nil when every island is taken (the player gets one as soon as somebody leaves).
function PlotService:AssignSlot(player: Player, teleportOnSpawn: boolean): number?
	local existing = slotsByPlayer[player]
	if existing then
		return existing.Index
	end
	if player.Parent ~= Players then
		return nil
	end

	local maxSlots = PlotSlots.GetSlotCount()
	local slotIndex = PlotSlots.FindFreeSlot(slotsByIndex, maxSlots)
	if not slotIndex then
		Logger:Warn("PLOT", "No free island for player %s (%d/%d taken), waiting for one to free up", player.Name, maxSlots, maxSlots)
		task.spawn(function()
			waitForProfile(player)
			if player.Parent == Players and not slotsByPlayer[player] then
				local payload: Types.PlotSlotAssignment = { SlotIndex = nil, Origin = nil, MaxSlots = maxSlots }
				Network.FireClient("PlotSlotAssigned", player, payload)
			end
		end)
		return nil
	end

	local folder = Instance.new("Folder")
	folder.Name = "Slot_" .. tostring(slotIndex)
	folder:SetAttribute("SlotIndex", slotIndex)
	folder:SetAttribute("OwnerUserId", player.UserId)
	folder:SetAttribute("OwnerName", player.Name)

	local decorationsFolder = Instance.new("Folder")
	decorationsFolder.Name = "Decorations"
	decorationsFolder.Parent = folder

	local slot: PlayerSlot = {
		Index = slotIndex,
		Owner = player,
		Folder = folder,
		DecorationsFolder = decorationsFolder,
		PlotModels = {},
		DecorationModels = {},
	}

	for _, plotConfig in ipairs(Config.PLOTS) do
		local worldPosition = PlotSlots.GetPlotWorldPosition(slotIndex, plotConfig)
		slot.PlotModels[plotConfig.Id] = spawnPlotGeometry(plotConfig, worldPosition, folder)
	end
	spawnOwnerSign(slotIndex, player, folder)

	slotsByIndex[slotIndex] = slot
	slotsByPlayer[player] = slot
	folder.Parent = plotsFolder -- Replicates the whole island content at once
	Logger:Info("PLOT", "Assigned island slot %d to player %s", slotIndex, player.Name)

	if teleportOnSpawn and Config.PLOT_SLOTS.TELEPORT_ON_FIRST_SPAWN then
		if player.Character then
			task.spawn(teleportToIsland, player, slot, player.Character)
		else
			player.CharacterAdded:Once(function(character)
				teleportToIsland(player, slot, character)
			end)
		end
	end

	-- Render the player's plot state, decorations and monsters once their profile is available
	task.spawn(function()
		local profile = waitForProfile(player)
		if slotsByPlayer[player] ~= slot then return end
		if profile then
			self:UpdateClientPlotVisuals(player)
			self:RenderPlayerDecorations(player)
			MonsterService:RenderPlacedMonsters(player)
		end
		local payload: Types.PlotSlotAssignment = {
			SlotIndex = slotIndex,
			Origin = PlotSlots.GetOrigin(slotIndex),
			MaxSlots = maxSlots,
		}
		Network.FireClient("PlotSlotAssigned", player, payload)
	end)

	return slotIndex
end

-- Destroys everything built for the player (plots, owner sign, decorations, placed monsters)
-- and frees the slot. Profile data is untouched: it is rebuilt on the next join.
function PlotService:ReleaseSlot(player: Player)
	local slot = slotsByPlayer[player]
	if not slot then return end

	slotsByPlayer[player] = nil
	slotsByIndex[slot.Index] = nil

	MonsterService:UnrenderAllForPlayer(player)
	slot.Folder:Destroy()
	table.clear(slot.PlotModels)
	table.clear(slot.DecorationModels)
	Logger:Info("PLOT", "Released island slot %d of player %s", slot.Index, player.Name)

	-- Hand the freed island to a player who joined while the server was full
	for _, waitingPlayer in ipairs(Players:GetPlayers()) do
		if waitingPlayer ~= player and not slotsByPlayer[waitingPlayer] then
			self:AssignSlot(waitingPlayer, false)
			break
		end
	end
end

function PlotService:GetPlayerSlotIndex(player: Player): number?
	local slot = slotsByPlayer[player]
	return slot and slot.Index or nil
end

-- World position of a plot's center on the player's island, or nil if the player has no island
function PlotService:GetPlotWorldPosition(player: Player, plotId: number): Vector3?
	local slot = slotsByPlayer[player]
	local plotConfig = self:GetPlotConfig(plotId)
	if not slot or not plotConfig then
		return nil
	end
	return PlotSlots.GetPlotWorldPosition(slot.Index, plotConfig)
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
	local slot = slotsByPlayer[player]
	if not profile or not slot then return end

	-- Only touches the models of this player's own island
	for plotId, model in pairs(slot.PlotModels) do
		local plotKey = tostring(plotId)
		local plotData = profile.Plots[plotKey]
		local isUnlocked = plotData ~= nil and plotData.IsUnlocked
		local config = self:GetPlotConfig(plotId)
		if not config then continue end

		-- Read by the owner's client (PlotController) to show/hide its purchase prompt
		model:SetAttribute("IsUnlocked", isUnlocked)

		local podium = model:FindFirstChild("SignPodium")
		if podium then
			local billboard = podium:FindFirstChild("PlotBillboard") :: BillboardGui

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

-- Builds a placed decoration on the owner's island (no-op if already built)
local function spawnDecorationModel(
	slot: PlayerSlot,
	plotConfig: Types.PlotConfig,
	decoConfig: Types.DecorationConfig,
	placedDeco: Types.PlacedDecoration
)
	if slot.DecorationModels[placedDeco.UUID] then return end
	local plotWorldPos = PlotSlots.GetPlotWorldPosition(slot.Index, plotConfig)
	local worldPos = plotWorldPos + Vector3.new(placedDeco.PositionX, placedDeco.PositionY, placedDeco.PositionZ)
	local model = buildProceduralDecorationModel(decoConfig, worldPos, placedDeco.RotationY or 0)
	model.Parent = slot.DecorationsFolder
	slot.DecorationModels[placedDeco.UUID] = model
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

	-- Bounds check within plot dimensions
	local halfX = (plotConfig.Size.X / 2) - 2
	local halfZ = (plotConfig.Size.Z / 2) - 2

	-- Grid snapping to Config.PLOT_GRID_SIZE
	local gridSize = Config.PLOT_GRID_SIZE or 4
	local snappedX = math.clamp(math.round(localX / gridSize) * gridSize, -halfX, halfX)
	local snappedZ = math.clamp(math.round(localZ / gridSize) * gridSize, -halfZ, halfZ)

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

	-- Spawn physical model on the player's island (if they have none, it is built when they get one)
	local slot = slotsByPlayer[player]
	if slot then
		spawnDecorationModel(slot, plotConfig, decoConfig, placedDeco)
	end

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
	local slot = slotsByPlayer[player]
	local model = slot and slot.DecorationModels[decorationUUID]
	if slot and model then
		model:Destroy()
		slot.DecorationModels[decorationUUID] = nil
	end

	Logger:Info("PLOT", "Player %s removed decoration %s from Plot %d", player.Name, decorationUUID, plotId)
	return true, nil
end

function PlotService:RenderPlayerDecorations(player: Player)
	local profile = PlayerDataService:GetProfile(player)
	local slot = slotsByPlayer[player]
	if not profile or not slot then return end

	for plotKey, plotData in pairs(profile.Plots) do
		local plotId = tonumber(plotKey) or plotData.Id
		local plotConfig = self:GetPlotConfig(plotId)
		if plotConfig and plotData.PlacedDecorations then
			for _, placedDeco in ipairs(plotData.PlacedDecorations) do
				local decoConfig = self:GetDecorationConfig(placedDeco.DecorationId)
				if decoConfig then
					spawnDecorationModel(slot, plotConfig, decoConfig, placedDeco)
				end
			end
		end
	end
end

return PlotService
