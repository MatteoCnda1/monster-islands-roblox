--!strict
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local MonsterDefinitions = require(ReplicatedStorage.Shared.MonsterDefinitions)
local ElementDefinitions = require(ReplicatedStorage.Shared.ElementDefinitions)
local Network = require(ReplicatedStorage.Shared.Utility.Network)

local PlayerDataService: any = nil

local placedMonstersFolder: Folder
local renderedMonsterModels: { [string]: Model } = {} -- Keyed by MonsterUUID

local MonsterService = {}

local function getPlacedMonstersFolder(): Folder
	local folder = Workspace:FindFirstChild("PlacedMonsters") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "PlacedMonsters"
		folder.Parent = Workspace
	end
	return folder
end

-- Procedural 3D Monster Model Generator (clean, stylized Roblox parts)
local function buildProceduralMonsterModel(monster: Types.MonsterInstance, definition: Types.MonsterDefinition): Model
	local model = Instance.new("Model")
	model.Name = string.format("Monster_%s_%s", definition.Id, string.sub(monster.UUID, 1, 6))

	local primaryColor = definition.PrimaryColor
	local secondaryColor = definition.SecondaryColor
	local scale = definition.ScaleMultiplier or 1.0

	-- Root & Torso
	local torso = Instance.new("Part")
	torso.Name = "HumanoidRootPart"
	torso.Size = Vector3.new(2.4 * scale, 1.8 * scale, 3.2 * scale)
	torso.Color = primaryColor
	torso.Material = Enum.Material.SmoothPlastic
	torso.Anchored = true
	torso.CanCollide = true
	torso.TopSurface = Enum.SurfaceType.Smooth
	torso.BottomSurface = Enum.SurfaceType.Smooth
	torso.Parent = model
	model.PrimaryPart = torso

	-- Head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.8 * scale, 1.6 * scale, 1.8 * scale)
	head.CFrame = torso.CFrame * CFrame.new(0, 0.8 * scale, -1.8 * scale)
	head.Color = primaryColor
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = true
	head.CanCollide = false
	head.Parent = model

	-- Glowing Eyes
	local leftEye = Instance.new("Part")
	leftEye.Name = "LeftEye"
	leftEye.Size = Vector3.new(0.35 * scale, 0.35 * scale, 0.2 * scale)
	leftEye.CFrame = head.CFrame * CFrame.new(-0.5 * scale, 0.2 * scale, -0.9 * scale)
	leftEye.Color = secondaryColor
	leftEye.Material = Enum.Material.Neon
	leftEye.Anchored = true
	leftEye.CanCollide = false
	leftEye.Parent = model

	local rightEye = Instance.new("Part")
	rightEye.Name = "RightEye"
	rightEye.Size = Vector3.new(0.35 * scale, 0.35 * scale, 0.2 * scale)
	rightEye.CFrame = head.CFrame * CFrame.new(0.5 * scale, 0.2 * scale, -0.9 * scale)
	rightEye.Color = secondaryColor
	rightEye.Material = Enum.Material.Neon
	rightEye.Anchored = true
	rightEye.CanCollide = false
	rightEye.Parent = model

	-- Species-specific stylistic features
	if definition.Id == "emberfox" or definition.Id == "voidfox" then
		-- Fox Ears
		for i, xOff in ipairs({ -0.6 * scale, 0.6 * scale }) do
			local ear = Instance.new("WedgePart")
			ear.Name = "Ear_" .. tostring(i)
			ear.Size = Vector3.new(0.4 * scale, 0.9 * scale, 0.5 * scale)
			ear.CFrame = head.CFrame * CFrame.new(xOff, 1.1 * scale, 0) * CFrame.Angles(0, math.pi, 0)
			ear.Color = primaryColor
			ear.Material = Enum.Material.SmoothPlastic
			ear.Anchored = true
			ear.CanCollide = false
			ear.Parent = model
		end
		-- Fluffy Flaming Tail
		local tail = Instance.new("Part")
		tail.Name = "FlameTail"
		tail.Size = Vector3.new(1.4 * scale, 1.4 * scale, 2.5 * scale)
		tail.CFrame = torso.CFrame * CFrame.new(0, 0.8 * scale, 2.2 * scale) * CFrame.Angles(math.rad(30), 0, 0)
		tail.Color = secondaryColor
		tail.Material = Enum.Material.Neon
		tail.Anchored = true
		tail.CanCollide = false
		tail.Parent = model

	elseif definition.Id == "mossaur" then
		-- Armor Shell Plates on back
		local shell = Instance.new("Part")
		shell.Name = "RockShell"
		shell.Size = Vector3.new(2.8 * scale, 1.2 * scale, 2.6 * scale)
		shell.CFrame = torso.CFrame * CFrame.new(0, 1.0 * scale, 0)
		shell.Color = secondaryColor
		shell.Material = Enum.Material.Slate
		shell.Anchored = true
		shell.CanCollide = false
		shell.Parent = model

	elseif definition.Id == "aquaphin" then
		-- Dorsal Fin
		local fin = Instance.new("WedgePart")
		fin.Name = "DorsalFin"
		fin.Size = Vector3.new(0.3 * scale, 1.2 * scale, 1.4 * scale)
		fin.CFrame = torso.CFrame * CFrame.new(0, 1.2 * scale, 0) * CFrame.Angles(0, math.pi, 0)
		fin.Color = secondaryColor
		fin.Material = Enum.Material.SmoothPlastic
		fin.Anchored = true
		fin.CanCollide = false
		fin.Parent = model

	elseif definition.Id == "zephlyn" or definition.Id == "noctyra" then
		-- Wings
		for i, mult in ipairs({ -1, 1 }) do
			local wing = Instance.new("Part")
			wing.Name = "Wing_" .. tostring(i)
			wing.Size = Vector3.new(2.6 * scale, 0.2 * scale, 1.8 * scale)
			wing.CFrame = torso.CFrame * CFrame.new(mult * 2.2 * scale, 0.8 * scale, 0) * CFrame.Angles(0, 0, mult * math.rad(20))
			wing.Color = secondaryColor
			wing.Material = (definition.Id == "noctyra") and Enum.Material.Neon or Enum.Material.SmoothPlastic
			wing.Anchored = true
			wing.CanCollide = false
			wing.Parent = model
		end
	end

	-- 4 Stylized Legs
	local legOffsets = {
		Vector3.new(-1.0 * scale, -1.0 * scale, -1.1 * scale),
		Vector3.new(1.0 * scale, -1.0 * scale, -1.1 * scale),
		Vector3.new(-1.0 * scale, -1.0 * scale, 1.1 * scale),
		Vector3.new(1.0 * scale, -1.0 * scale, 1.1 * scale),
	}
	for i, offset in ipairs(legOffsets) do
		local leg = Instance.new("Part")
		leg.Name = "Leg_" .. tostring(i)
		leg.Size = Vector3.new(0.6 * scale, 1.2 * scale, 0.6 * scale)
		leg.CFrame = torso.CFrame * CFrame.new(offset)
		leg.Color = primaryColor
		leg.Material = Enum.Material.SmoothPlastic
		leg.Anchored = true
		leg.CanCollide = false
		leg.Parent = model
	end

	-- Billboard GUI for name, level, element
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MonsterBillboard"
	billboard.Size = UDim2.new(0, 160, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 2.8 * scale, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 60
	billboard.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = string.format("%s (Lv. %d)", monster.Nickname or definition.DisplayName, monster.Level)
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = billboard

	local elementLabel = Instance.new("TextLabel")
	elementLabel.Name = "ElementLabel"
	elementLabel.Size = UDim2.new(1, 0, 0.5, 0)
	elementLabel.Position = UDim2.new(0, 0, 0.5, 0)
	elementLabel.BackgroundTransparency = 1
	elementLabel.Text = table.concat(definition.Elements, " / ")
	elementLabel.TextColor3 = secondaryColor
	elementLabel.TextScaled = true
	elementLabel.Font = Enum.Font.GothamMedium
	elementLabel.Parent = billboard

	return model
end

function MonsterService:Init()
	Logger:Info("MONSTER", "Initializing MonsterService...")
	PlayerDataService = require(script.Parent.PlayerDataService)
	placedMonstersFolder = getPlacedMonstersFolder()

	-- Remotes
	Network.HandleFunction("GetPlayerMonsters", function(player: Player)
		local profile = PlayerDataService:GetProfile(player)
		return profile and profile.Monsters or {}
	end)

	Network.HandleFunction("SetPlayerTeam", function(player: Player, teamUUIDs: any)
		if typeof(teamUUIDs) ~= "table" then return false, "Invalid payload" end
		return self:SetTeam(player, teamUUIDs)
	end)
end

function MonsterService:Start()
	-- Render existing placed monsters for joined players
	Network.HandleEvent("RequestRenderPlacedMonsters", function(player: Player)
		local profile = PlayerDataService:GetProfile(player)
		if not profile then return end

		for uuid, monster in pairs(profile.Monsters) do
			if monster.AssignedPlotId then
				self:RenderMonsterOnPlot(player, uuid, monster.AssignedPlotId)
			end
		end
	end)
end

function MonsterService:CreateMonster(
	player: Player,
	speciesId: string,
	customIVs: Types.MonsterIVs?,
	parents: { string }?,
	generation: number?
): (boolean, Types.MonsterInstance?)
	local definition = MonsterDefinitions.Get(speciesId)
	if not definition then
		Logger:Error("MONSTER", "Failed to create monster: species %s does not exist", speciesId)
		return false, nil
	end

	local ivs = customIVs or {
		Health = math.random(0, 15),
		Attack = math.random(0, 15),
		Defense = math.random(0, 15),
		Speed = math.random(0, 15),
	}

	local calculatedStats, maxHealth = MonsterDefinitions.CalculateStats(speciesId, 1, ivs)
	local monsterUUID = HttpService:GenerateGUID(false)

	local newMonster: Types.MonsterInstance = {
		UUID = monsterUUID,
		SpeciesId = speciesId,
		Nickname = definition.DisplayName,
		Level = 1,
		XP = 0,
		CurrentHealth = maxHealth,
		MaxHealth = maxHealth,
		IVs = ivs,
		CalculatedStats = calculatedStats,
		SkillsEquipped = table.clone(definition.Skills),
		Parents = parents,
		Generation = generation or 1,
		AssignedPlotId = nil,
		CreatedAt = os.time(),
	}

	local success = PlayerDataService:UpdateProfile(player, function(profile)
		profile.Monsters[monsterUUID] = newMonster
	end)

	if success then
		Logger:Info("MONSTER", "Created monster %s (%s) for player %s", definition.DisplayName, monsterUUID, player.Name)
		Network.FireClient("MonsterAcquired", player, newMonster)
		return true, newMonster
	end

	return false, nil
end

function MonsterService:SetTeam(player: Player, teamUUIDs: { string }): (boolean, string?)
	if #teamUUIDs == 0 then
		return false, "Team cannot be empty"
	end
	if #teamUUIDs > Config.MAX_TEAM_SIZE then
		return false, string.format("Team exceeds maximum size of %d", Config.MAX_TEAM_SIZE)
	end

	local profile = PlayerDataService:GetProfile(player)
	if not profile then return false, "No profile" end

	-- Validate ownership of each monster
	for _, uuid in ipairs(teamUUIDs) do
		if not profile.Monsters[uuid] then
			return false, "Player does not own all designated monsters"
		end
	end

	PlayerDataService:UpdateProfile(player, function(prof)
		prof.TeamMonsterUUIDs = teamUUIDs
	end)

	Logger:Info("MONSTER", "Player %s updated battle team with %d monsters", player.Name, #teamUUIDs)
	return true, nil
end

function MonsterService:RenderMonsterOnPlot(player: Player, monsterUUID: string, plotId: number)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then return end

	local monster = profile.Monsters[monsterUUID]
	if not monster then return end

	local definition = MonsterDefinitions.Get(monster.SpeciesId)
	if not definition then return end

	-- Unrender existing model if present
	self:UnrenderMonsterFromPlot(player, monsterUUID)

	local plotConfig: Types.PlotConfig? = nil
	for _, cfg in ipairs(Config.PLOTS) do
		if cfg.Id == plotId then
			plotConfig = cfg
			break
		end
	end
	if not plotConfig then return end

	local model = buildProceduralMonsterModel(monster, definition)
	-- Offset position slightly within plot
	local offsetX = (math.random() - 0.5) * (plotConfig.Size.X * 0.4)
	local offsetZ = (math.random() - 0.5) * (plotConfig.Size.Z * 0.4)
	local spawnPos = plotConfig.WorldPosition + Vector3.new(offsetX, (plotConfig.Size.Y / 2) + 2.5, offsetZ)

	if model.PrimaryPart then
		model:SetPrimaryPartCFrame(CFrame.new(spawnPos) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0))
	end

	model.Parent = placedMonstersFolder
	renderedMonsterModels[monsterUUID] = model

	-- Idle subtle hovering or breathing effect
	task.spawn(function()
		local baseCFrame = model.PrimaryPart and model.PrimaryPart.CFrame
		while model.Parent and baseCFrame do
			for angle = 0, 360, 10 do
				if not model.Parent or not model.PrimaryPart then break end
				local bobY = math.sin(math.rad(angle)) * 0.25
				model:SetPrimaryPartCFrame(baseCFrame * CFrame.new(0, bobY, 0))
				task.wait(0.05)
			end
		end
	end)
end

function MonsterService:UnrenderMonsterFromPlot(player: Player, monsterUUID: string)
	local existingModel = renderedMonsterModels[monsterUUID]
	if existingModel then
		existingModel:Destroy()
		renderedMonsterModels[monsterUUID] = nil
	end
end

function MonsterService:BuildBattleMonsterModel(monster: Types.MonsterInstance): Model
	local definition = MonsterDefinitions.Get(monster.SpeciesId)
	if not definition then
		error("Unknown species: " .. monster.SpeciesId)
	end
	return buildProceduralMonsterModel(monster, definition)
end

return MonsterService
