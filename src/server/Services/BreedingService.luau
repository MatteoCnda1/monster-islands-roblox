--!strict
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local MonsterDefinitions = require(ReplicatedStorage.Shared.MonsterDefinitions)
local BreedingMath = require(ReplicatedStorage.Shared.BreedingMath)
local PlotSlots = require(ReplicatedStorage.Shared.PlotSlots)
local Network = require(ReplicatedStorage.Shared.Utility.Network)
local Signal = require(ReplicatedStorage.Shared.Utility.Signal)

local PlayerDataService: any = nil
local MonsterService: any = nil
local PlotService: any = nil

-- Physical eggs laid in each player's island nest (issue #29), keyed by player then session id.
-- EggIndex is the egg's spot in the nest (PlotSlots.GetNestEggOffset), kept while the egg exists.
type PhysicalEgg = {
	Model: Model,
	EggIndex: number,
}
local physicalEggsByPlayer: { [Player]: { [string]: PhysicalEgg } } = {}
-- Session ids whose hatch (shake VFX + claim) is in progress, against double triggers
local hatchingSessions: { [string]: boolean } = {}

local HATCH_SHAKE_STEPS = 8
local HATCH_SHAKE_STEP_SECONDS = 0.06

local BreedingService = {}

-- Fired after an egg has been hatched and the new monster created: (player, newMonster)
BreedingService.EggHatchedSignal = Signal.new() :: Signal.Signal<Player, Types.MonsterInstance>

local function isEggReady(session: Types.BreedingSession): boolean
	return os.time() >= session.EggReadyAt
end

-- Lowest nest spot not used by the player's other eggs, so an egg keeps its place when another hatches
local function findFreeEggIndex(eggs: { [string]: PhysicalEgg }): number
	local used: { [number]: boolean } = {}
	for _, egg in pairs(eggs) do
		used[egg.EggIndex] = true
	end
	local eggIndex = 1
	while used[eggIndex] do
		eggIndex += 1
	end
	return eggIndex
end

-- The egg model only carries visuals and attributes: the hatch ProximityPrompt is created client-side
-- by PlotController for the owner only (OwnerUserId / IsReady attributes), and goes through the
-- "ClaimBreedingEgg" remote, which re-validates ownership and readiness.
local function buildProceduralEggModel(session: Types.BreedingSession, owner: Player, eggPos: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Egg_" .. session.Id
	model:SetAttribute("BreedingSessionId", session.Id)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("IsReady", isEggReady(session))

	local def = MonsterDefinitions.Get(session.EggSpeciesId)
	local primaryColor = def and def.PrimaryColor or Color3.fromRGB(240, 200, 150)
	local secondaryColor = def and def.SecondaryColor or Color3.fromRGB(255, 100, 120)
	local displayName = def and def.DisplayName or session.EggSpeciesId
	model:SetAttribute("SpeciesDisplayName", displayName)

	-- Base egg shell
	local eggShell = Instance.new("Part")
	eggShell.Name = "EggShell"
	eggShell.Shape = Enum.PartType.Ball
	eggShell.Size = Vector3.new(3.0, 4.2, 3.0)
	eggShell.Position = eggPos
	eggShell.Color = primaryColor
	eggShell.Material = Enum.Material.SmoothPlastic
	eggShell.Anchored = true
	eggShell.CanCollide = true
	eggShell.Parent = model
	model.PrimaryPart = eggShell

	-- Luminous elemental ring around the egg
	local ring = Instance.new("Part")
	ring.Name = "ElementalRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.5, 3.3, 3.3)
	ring.CFrame = eggShell.CFrame * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = secondaryColor
	ring.Material = Enum.Material.Neon
	ring.Anchored = true
	ring.CanCollide = false
	ring.Parent = model

	-- Floating BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EggBillboard"
	billboard.Size = UDim2.new(0, 180, 0, 55)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 70
	billboard.Parent = eggShell

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0.45, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = string.format("🥚 %s Egg", displayName)
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.Parent = billboard

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0.45, 0)
	statusLabel.Position = UDim2.new(0, 0, 0.5, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextScaled = true
	statusLabel.Parent = billboard

	-- Live countdown and ready state (the attribute drives the owner's client-side prompt)
	task.spawn(function()
		while model.Parent do
			if isEggReady(session) then
				statusLabel.Text = "✨ READY TO HATCH! ✨"
				statusLabel.TextColor3 = Color3.fromRGB(100, 255, 120)
				model:SetAttribute("IsReady", true)
			else
				statusLabel.Text = string.format("Incubating (%ds)", session.EggReadyAt - os.time())
				statusLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
				model:SetAttribute("IsReady", false)
			end
			task.wait(1)
		end
	end)

	return model
end

-- Validates that the player can hatch this egg now: (session, nil) or (nil, reason)
local function validateClaim(profile: Types.PlayerData, sessionId: string): (Types.BreedingSession?, string?)
	local session = profile.BreedingSessions[sessionId]
	if not session then
		return nil, "Breeding session does not exist"
	end
	if session.IsHatched then
		return nil, "Egg already claimed"
	end
	if not isEggReady(session) then
		return nil, string.format("Egg is still incubating! %d seconds remaining", session.EggReadyAt - os.time())
	end
	return session, nil
end

function BreedingService:Init()
	Logger:Info("BREEDING", "Initializing BreedingService...")
	PlayerDataService = require(script.Parent.PlayerDataService)
	MonsterService = require(script.Parent.MonsterService)
	PlotService = require(script.Parent.PlotService)

	-- Remotes
	Network.HandleFunction("StartBreeding", function(player: Player, payload: any)
		if typeof(payload) ~= "table" or typeof(payload.ParentA_UUID) ~= "string" or typeof(payload.ParentB_UUID) ~= "string" then
			return false, "Invalid breeding arguments"
		end
		return self:StartBreeding(player, payload.ParentA_UUID, payload.ParentB_UUID)
	end)

	-- Used by both the Breeding tab button and the hatch prompt of the owner's egg (PlotController).
	-- The session is looked up in the caller's own profile, so nobody can hatch someone else's egg.
	Network.HandleFunction("ClaimBreedingEgg", function(player: Player, sessionId: any)
		if typeof(sessionId) ~= "string" then
			return false, "Invalid session ID"
		end
		return self:HatchEggWithVFX(player, sessionId)
	end)
end

function BreedingService:Start()
	-- Eggs are (re)laid by PlotService once the player's island is built and their profile loaded,
	-- and removed with the island when they leave. This request is an idempotent client-side safety net.
	Network.HandleEvent("RefreshBreedingEggs", function(player: Player)
		self:RestoreActiveEggs(player)
	end)
end

-- Lays the egg in the owner's island nest. Without an island (server full) nothing is spawned: the egg
-- still incubates in the profile and is laid by RestoreActiveEggs once an island is assigned.
function BreedingService:SpawnPhysicalEgg(player: Player, session: Types.BreedingSession)
	local eggs = physicalEggsByPlayer[player]
	if eggs and eggs[session.Id] then
		return
	end

	local slotIndex = PlotService:GetPlayerSlotIndex(player)
	local eggsFolder = PlotService:GetNestEggsFolder(player)
	if not slotIndex or not eggsFolder then
		Logger:Debug("BREEDING", "No island for player %s yet: egg %s will be laid once one is assigned", player.Name, session.Id)
		return
	end

	if not eggs then
		eggs = {}
		physicalEggsByPlayer[player] = eggs
	end

	local eggIndex = findFreeEggIndex(eggs)
	local nestTop = PlotSlots.GetNestTopWorldPosition(slotIndex)
	local offset = PlotSlots.GetNestEggOffset(eggIndex)
	local eggPos = nestTop + offset + Vector3.new(0, 1.6, 0) -- Egg (4.2 tall) slightly sunk in the bowl

	local model = buildProceduralEggModel(session, player, eggPos)
	model.Parent = eggsFolder
	eggs[session.Id] = { Model = model, EggIndex = eggIndex }
end

function BreedingService:DestroyPhysicalEgg(player: Player, sessionId: string)
	local eggs = physicalEggsByPlayer[player]
	local egg = eggs and eggs[sessionId]
	if eggs and egg then
		egg.Model:Destroy()
		eggs[sessionId] = nil
	end
end

-- Called by PlotService when the player's island is released (player leaving)
function BreedingService:DespawnAllEggsForPlayer(player: Player)
	local eggs = physicalEggsByPlayer[player]
	if not eggs then return end
	for sessionId, egg in pairs(eggs) do
		egg.Model:Destroy()
		hatchingSessions[sessionId] = nil
	end
	physicalEggsByPlayer[player] = nil
end

-- Hatches one of the player's own ready eggs: shake + flash on the physical egg (if laid), then claim
function BreedingService:HatchEggWithVFX(player: Player, sessionId: string): (boolean, any)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then return false, "No player profile" end

	local _, reason = validateClaim(profile, sessionId)
	if reason then
		return false, reason
	end
	if hatchingSessions[sessionId] then
		return false, "Egg is already hatching"
	end
	hatchingSessions[sessionId] = true

	local eggs = physicalEggsByPlayer[player]
	local egg = eggs and eggs[sessionId]
	local part = egg and egg.Model.PrimaryPart
	if part then
		local origCFrame = part.CFrame
		-- Dramatic egg wobbling crack shake
		for i = 1, HATCH_SHAKE_STEPS do
			local offsetAngle = ((i % 2 == 0) and 1 or -1) * math.rad(14)
			part.CFrame = origCFrame * CFrame.Angles(0, 0, offsetAngle)
			task.wait(HATCH_SHAKE_STEP_SECONDS)
		end
		if part.Parent then
			part.CFrame = origCFrame

			-- Flash light burst
			local flash = Instance.new("PointLight")
			flash.Color = Color3.fromRGB(255, 255, 200)
			flash.Brightness = 8
			flash.Range = 25
			flash.Parent = part
		end
	end

	local ok, success, result = pcall(self.ClaimHatchedEgg, self, player, sessionId)
	hatchingSessions[sessionId] = nil
	if not ok then
		Logger:Error("BREEDING", "Hatching egg %s of player %s failed: %s", sessionId, player.Name, tostring(success))
		return false, "Failed to hatch monster"
	end
	return success, result
end

function BreedingService:RestoreActiveEggs(player: Player)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then return end

	-- Oldest sessions first, so eggs get the same nest spots on every rebuild
	local sessions: { Types.BreedingSession } = {}
	for _, session in pairs(profile.BreedingSessions) do
		if not session.IsHatched then
			table.insert(sessions, session)
		end
	end
	table.sort(sessions, function(a, b)
		if a.StartedAt ~= b.StartedAt then
			return a.StartedAt < b.StartedAt
		end
		return a.Id < b.Id
	end)

	for _, session in ipairs(sessions) do
		self:SpawnPhysicalEgg(player, session)
	end
end

function BreedingService:StartBreeding(player: Player, parentUUID_A: string, parentUUID_B: string): (boolean, string?)
	if parentUUID_A == parentUUID_B then
		return false, "Cannot breed a monster with itself"
	end

	local profile = PlayerDataService:GetProfile(player)
	if not profile then return false, "No player profile" end

	local parentA = profile.Monsters[parentUUID_A]
	local parentB = profile.Monsters[parentUUID_B]
	if not parentA or not parentB then
		return false, "You do not own both specified monsters"
	end

	-- Check if either parent is already busy in an active breeding session
	for _, session in pairs(profile.BreedingSessions) do
		if not session.IsHatched then
			if session.ParentA_UUID == parentUUID_A or session.ParentB_UUID == parentUUID_A or
			   session.ParentA_UUID == parentUUID_B or session.ParentB_UUID == parentUUID_B then
				return false, "One of the chosen monsters is already in a breeding session"
			end
		end
	end

	-- Check elemental compatibility
	local defA = MonsterDefinitions.Get(parentA.SpeciesId)
	local defB = MonsterDefinitions.Get(parentB.SpeciesId)
	if not defA or not defB then return false, "Invalid species definition" end

	if not BreedingMath.AreCompatible(defA, defB) then
		return false, "These two species are not elementally compatible for breeding"
	end

	-- Calculate breeding outcome
	local childSpecies, isMutation = BreedingMath.DetermineChildSpecies(parentA.SpeciesId, parentB.SpeciesId)
	if isMutation then
		Logger:Info("BREEDING", "Discovery! Rare mutation recipe triggered: %s", childSpecies)
	end
	local childIVs = BreedingMath.InheritIVs(parentA.IVs, parentB.IVs)
	local duration = Config.BREEDING.DEFAULT_BREED_TIME_SECONDS
	local now = os.time()
	local sessionId = HttpService:GenerateGUID(false)

	local newSession: Types.BreedingSession = {
		Id = sessionId,
		ParentA_UUID = parentUUID_A,
		ParentB_UUID = parentUUID_B,
		StartedAt = now,
		DurationSeconds = duration,
		EggReadyAt = now + duration,
		EggSpeciesId = childSpecies,
		EggIVs = childIVs,
		IsCompleted = false,
		IsHatched = false,
	}

	PlayerDataService:UpdateProfile(player, function(prof)
		prof.BreedingSessions[sessionId] = newSession
	end)

	-- Lay the physical egg in the player's island nest
	self:SpawnPhysicalEgg(player, newSession)

	Logger:Info("BREEDING", "Player %s started breeding %s + %s -> Session %s (Ready in %ds)",
		player.Name, defA.DisplayName, defB.DisplayName, sessionId, duration)

	Network.FireClient("BreedingStarted", player, newSession)
	return true, nil
end

function BreedingService:ClaimHatchedEgg(player: Player, sessionId: string): (boolean, any)
	local profile = PlayerDataService:GetProfile(player)
	if not profile then return false, "No player profile" end

	local session, reason = validateClaim(profile, sessionId)
	if not session then
		return false, reason
	end

	local parentA = profile.Monsters[session.ParentA_UUID]
	local parentB = profile.Monsters[session.ParentB_UUID]
	local generation = 2
	if parentA and parentB then
		generation = math.max(parentA.Generation, parentB.Generation) + 1
	end

	-- Create the child monster
	local success, newMonster = MonsterService:CreateMonster(
		player,
		session.EggSpeciesId,
		session.EggIVs,
		{ session.ParentA_UUID, session.ParentB_UUID },
		generation
	)

	if not success or not newMonster then
		return false, "Failed to hatch monster"
	end

	PlayerDataService:UpdateProfile(player, function(prof)
		local s = prof.BreedingSessions[sessionId]
		if s then
			s.IsCompleted = true
			s.IsHatched = true
		end
	end)

	-- Remove the physical egg from the nest
	self:DestroyPhysicalEgg(player, sessionId)

	Logger:Info("BREEDING", "Player %s hatched egg! New monster: %s (Gen %d, UUID: %s)",
		player.Name, newMonster.SpeciesId, generation, newMonster.UUID)

	Network.FireClient("EggHatched", player, newMonster)
	BreedingService.EggHatchedSignal:Fire(player, newMonster)
	return true, newMonster
end

return BreedingService
