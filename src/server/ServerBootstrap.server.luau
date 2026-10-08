--!strict
-- ServerBootstrap: Master entry point for Monster Islands server

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Config = require(ReplicatedStorage.Shared.Config)
local PlotSlots = require(ReplicatedStorage.Shared.PlotSlots)

-- Procedural Starter Map Generator (Generates the 3D playable island directly in Workspace)
local function buildStarterWorld()
	local mapFolder = Workspace:FindFirstChild("WorldMap")
	if mapFolder then return end -- Already generated

	Logger:Info("MAP", "Building starter 3D world geometry...")
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "WorldMap"
	mapFolder.Parent = Workspace

	-- 1. Main Hub Island (Village Central Ground)
	local mainIsland = Instance.new("Part")
	mainIsland.Name = "MainIslandBase"
	mainIsland.Size = Vector3.new(220, 4, 220)
	mainIsland.Position = Vector3.new(0, 0, 0)
	mainIsland.Anchored = true
	mainIsland.Material = Enum.Material.Grass
	mainIsland.Color = Color3.fromRGB(75, 155, 70)
	mainIsland.TopSurface = Enum.SurfaceType.Smooth
	mainIsland.BottomSurface = Enum.SurfaceType.Smooth
	mainIsland.Parent = mapFolder

	-- Sand ring around island
	local sandRing = Instance.new("Part")
	sandRing.Name = "SandBeaches"
	sandRing.Size = Vector3.new(240, 2, 240)
	sandRing.Position = Vector3.new(0, -1, 0)
	sandRing.Anchored = true
	sandRing.Material = Enum.Material.Sand
	sandRing.Color = Color3.fromRGB(225, 205, 145)
	sandRing.TopSurface = Enum.SurfaceType.Smooth
	sandRing.BottomSurface = Enum.SurfaceType.Smooth
	sandRing.Parent = mapFolder

	-- Ocean Water Plane
	local waterPlane = Instance.new("Part")
	waterPlane.Name = "OceanPlane"
	waterPlane.Size = Vector3.new(1000, 2, 1000)
	waterPlane.Position = Vector3.new(0, -2, 0)
	waterPlane.Anchored = true
	waterPlane.Material = Enum.Material.Glass
	waterPlane.Color = Color3.fromRGB(30, 120, 200)
	waterPlane.Transparency = 0.35
	waterPlane.CanCollide = false
	waterPlane.Parent = mapFolder

	-- 2. Player Spawn Location
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "VillageSpawn"
	spawnLocation.Size = Vector3.new(14, 1.2, 14)
	spawnLocation.Position = Vector3.new(0, 2.6, 0)
	spawnLocation.Anchored = true
	spawnLocation.Material = Enum.Material.Cobblestone
	spawnLocation.Color = Color3.fromRGB(160, 160, 170)
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.TopSurface = Enum.SurfaceType.Smooth
	spawnLocation.BottomSurface = Enum.SurfaceType.Smooth
	spawnLocation.Parent = mapFolder

	-- Central Plaza Monument / Fountain Base
	local plazaMonument = Instance.new("Part")
	plazaMonument.Name = "PlazaMonument"
	plazaMonument.Size = Vector3.new(6, 6, 6)
	plazaMonument.Position = Vector3.new(0, 5.5, 0)
	plazaMonument.Anchored = true
	plazaMonument.Material = Enum.Material.Marble
	plazaMonument.Color = Color3.fromRGB(240, 240, 245)
	plazaMonument.Parent = mapFolder

	local monumentCrystal = Instance.new("Part")
	monumentCrystal.Name = "MonumentCrystal"
	monumentCrystal.Size = Vector3.new(3, 4, 3)
	monumentCrystal.Position = Vector3.new(0, 10.5, 0)
	monumentCrystal.Anchored = true
	monumentCrystal.Material = Enum.Material.Neon
	monumentCrystal.Color = Color3.fromRGB(80, 210, 240)
	monumentCrystal.Parent = mapFolder

	-- 3. Stone Pathways linking Spawn to Plot quadrants
	local pathConfigs = {
		{ Size = Vector3.new(10, 0.4, 70), Pos = Vector3.new(0, 2.2, -45) },
		{ Size = Vector3.new(10, 0.4, 70), Pos = Vector3.new(0, 2.2, 45) },
		{ Size = Vector3.new(70, 0.4, 10), Pos = Vector3.new(-45, 2.2, 0) },
		{ Size = Vector3.new(70, 0.4, 10), Pos = Vector3.new(45, 2.2, 0) },
	}
	for i, pCfg in ipairs(pathConfigs) do
		local path = Instance.new("Part")
		path.Name = "StonePath_" .. tostring(i)
		path.Size = pCfg.Size
		path.Position = pCfg.Pos
		path.Anchored = true
		path.Material = Enum.Material.Cobblestone
		path.Color = Color3.fromRGB(150, 150, 155)
		path.TopSurface = Enum.SurfaceType.Smooth
		path.Parent = mapFolder
	end

	-- 4. Breeding Sanctuary Building (West area). Decorative landmark only: since issue #29 every player
	-- breeds from the Breeding tab and their eggs incubate in the nest of their own island (PlotService).
	local breedingSanctuary = Instance.new("Model")
	breedingSanctuary.Name = "BreedingSanctuary"

	local bBase = Instance.new("Part")
	bBase.Name = "BreedingFloor"
	bBase.Size = Vector3.new(28, 2, 28)
	bBase.Position = Vector3.new(-85, 2, 0)
	bBase.Anchored = true
	bBase.Material = Enum.Material.WoodPlanks
	bBase.Color = Color3.fromRGB(130, 85, 45)
	bBase.Parent = breedingSanctuary

	local bRoof = Instance.new("Part")
	bRoof.Name = "BreedingRoof"
	bRoof.Size = Vector3.new(32, 2, 32)
	bRoof.Position = Vector3.new(-85, 14, 0)
	bRoof.Anchored = true
	bRoof.Material = Enum.Material.Wood
	bRoof.Color = Color3.fromRGB(90, 55, 30)
	bRoof.Parent = breedingSanctuary

	-- Pillars
	for _, pX in ipairs({ -97, -73 }) do
		for _, pZ in ipairs({ -12, 12 }) do
			local bPillar = Instance.new("Part")
			bPillar.Size = Vector3.new(2, 10, 2)
			bPillar.Position = Vector3.new(pX, 8, pZ)
			bPillar.Anchored = true
			bPillar.Material = Enum.Material.Stone
			bPillar.Color = Color3.fromRGB(140, 140, 145)
			bPillar.Parent = breedingSanctuary
		end
	end

	-- Decorative nest bowl in the center of the sanctuary (no egg is laid here)
	local nest = Instance.new("Part")
	nest.Name = "BreedingNest"
	nest.Size = Vector3.new(8, 2, 8)
	nest.Position = Vector3.new(-85, 4, 0)
	nest.Anchored = true
	nest.Material = Enum.Material.Fabric
	nest.Color = Color3.fromRGB(200, 160, 90)
	nest.Parent = breedingSanctuary

	local bSign = Instance.new("BillboardGui")
	bSign.Size = UDim2.new(0, 220, 0, 60)
	bSign.StudsOffset = Vector3.new(0, 4, 0)
	bSign.AlwaysOnTop = true
	bSign.MaxDistance = 80
	bSign.Parent = nest

	local bLabel = Instance.new("TextLabel")
	bLabel.Size = UDim2.new(1, 0, 1, 0)
	bLabel.BackgroundTransparency = 1
	bLabel.Text = "Breeding Sanctuary\nYour eggs hatch in your island nest"
	bLabel.TextColor3 = Color3.fromRGB(255, 230, 120)
	bLabel.TextScaled = true
	bLabel.Font = Enum.Font.GothamBold
	bLabel.Parent = bSign

	breedingSanctuary.Parent = mapFolder

	-- 5. PvP Battle Arena Platform (North area)
	local battleArena = Instance.new("Model")
	battleArena.Name = "BattleArena"

	local arenaFloor = Instance.new("Part")
	arenaFloor.Name = "ArenaFloor"
	arenaFloor.Size = Vector3.new(60, 4, 60)
	arenaFloor.Position = Vector3.new(0, 2, -120)
	arenaFloor.Anchored = true
	arenaFloor.Material = Enum.Material.Basalt
	arenaFloor.Color = Color3.fromRGB(50, 50, 60)
	arenaFloor.Parent = battleArena

	-- Podium Player 1 (Blue)
	local pod1 = Instance.new("Part")
	pod1.Name = "PodiumPlayer1"
	pod1.Size = Vector3.new(10, 2, 10)
	pod1.Position = Vector3.new(-18, 5, -120)
	pod1.Anchored = true
	pod1.Material = Enum.Material.Neon
	pod1.Color = Color3.fromRGB(40, 120, 240)
	pod1.Parent = battleArena

	-- Podium Player 2 (Red)
	local pod2 = Instance.new("Part")
	pod2.Name = "PodiumPlayer2"
	pod2.Size = Vector3.new(10, 2, 10)
	pod2.Position = Vector3.new(18, 5, -120)
	pod2.Anchored = true
	pod2.Material = Enum.Material.Neon
	pod2.Color = Color3.fromRGB(240, 50, 50)
	pod2.Parent = battleArena

	local arenaSign = Instance.new("BillboardGui")
	arenaSign.Size = UDim2.new(0, 220, 0, 60)
	arenaSign.StudsOffset = Vector3.new(0, 12, 0)
	arenaSign.AlwaysOnTop = true
	arenaSign.MaxDistance = 120
	arenaSign.Parent = arenaFloor

	local aLabel = Instance.new("TextLabel")
	aLabel.Size = UDim2.new(1, 0, 1, 0)
	aLabel.BackgroundTransparency = 1
	aLabel.Text = "PvP Battle Arena"
	aLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	aLabel.TextScaled = true
	aLabel.Font = Enum.Font.GothamBold
	aLabel.Parent = arenaSign

	battleArena.Parent = mapFolder

	-- 6. Player plot islands: one annex island per slot, linked to the village by a bridge.
	-- PlotService assigns a slot to each player and builds their plots on it (issue #21).
	local islandsFolder = Instance.new("Folder")
	islandsFolder.Name = "PlotIslands"

	local islandSize = Config.PLOT_SLOTS.ISLAND_SIZE
	for slotIndex = 1, PlotSlots.GetSlotCount() do
		local origin = PlotSlots.GetOrigin(slotIndex)

		local island = Instance.new("Part")
		island.Name = "PlotIsland_" .. tostring(slotIndex)
		island.Size = islandSize
		island.Position = origin
		island.Anchored = true
		island.Material = Enum.Material.Grass
		island.Color = Color3.fromRGB(75, 155, 70)
		island.TopSurface = Enum.SurfaceType.Smooth
		island.BottomSurface = Enum.SurfaceType.Smooth
		island.Parent = islandsFolder

		local islandSand = Instance.new("Part")
		islandSand.Name = "PlotIslandBeach_" .. tostring(slotIndex)
		islandSand.Size = Vector3.new(islandSize.X + 10, 2, islandSize.Z + 10)
		islandSand.Position = origin + Vector3.new(0, -1, 0)
		islandSand.Anchored = true
		islandSand.Material = Enum.Material.Sand
		islandSand.Color = Color3.fromRGB(225, 205, 145)
		islandSand.TopSurface = Enum.SurfaceType.Smooth
		islandSand.BottomSurface = Enum.SurfaceType.Smooth
		islandSand.Parent = islandsFolder

		local bridgeStart, bridgeEnd = PlotSlots.GetBridgeEndpoints(slotIndex)
		local bridgeLength = (bridgeEnd - bridgeStart).Magnitude
		local bridgeMid = (bridgeStart + bridgeEnd) / 2 + Vector3.new(0, 2, 0) -- Top at y = 2.5 (hub paths: 2.4)
		local bridge = Instance.new("Part")
		bridge.Name = "PlotBridge_" .. tostring(slotIndex)
		bridge.Size = Vector3.new(Config.PLOT_SLOTS.BRIDGE_WIDTH, 1, bridgeLength)
		bridge.CFrame = CFrame.lookAt(bridgeMid, bridgeMid + (bridgeEnd - bridgeStart))
		bridge.Anchored = true
		bridge.Material = Enum.Material.WoodPlanks
		bridge.Color = Color3.fromRGB(150, 105, 60)
		bridge.TopSurface = Enum.SurfaceType.Smooth
		bridge.BottomSurface = Enum.SurfaceType.Smooth
		bridge.Parent = islandsFolder
	end

	islandsFolder.Parent = mapFolder

	Logger:Info("MAP", "Starter 3D world geometry generated successfully.")
end

-- Initialize Server
Logger:Info("BOOTSTRAP", "Bootstrapping Monster Islands Server...")

-- 1. Build world environment
buildStarterWorld()

-- 2. Services Catalogue
local servicesFolder = script.Parent.Services

local PlayerDataService = require(servicesFolder.PlayerDataService)
local EconomyService = require(servicesFolder.EconomyService)
local MonsterService = require(servicesFolder.MonsterService)
local PlotService = require(servicesFolder.PlotService)
local BreedingService = require(servicesFolder.BreedingService)
local CombatService = require(servicesFolder.CombatService)
local MatchmakingService = require(servicesFolder.MatchmakingService)
local InventoryService = require(servicesFolder.InventoryService)
local QuestService = require(servicesFolder.QuestService)

local services = {
	PlayerDataService,
	EconomyService,
	MonsterService,
	PlotService,
	BreedingService,
	CombatService,
	MatchmakingService,
	InventoryService,
	QuestService,
}

-- Init phase
Logger:Info("BOOTSTRAP", "Running :Init() on all services...")
for _, service in ipairs(services) do
	if typeof(service.Init) == "function" then
		service:Init()
	end
end

-- Start phase
Logger:Info("BOOTSTRAP", "Running :Start() on all services...")
for _, service in ipairs(services) do
	if typeof(service.Start) == "function" then
		service:Start()
	end
end

Logger:Info("BOOTSTRAP", "=== Monster Islands Server Ready ===")
