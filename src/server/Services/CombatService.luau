--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local MonsterDefinitions = require(ReplicatedStorage.Shared.MonsterDefinitions)
local AttackDefinitions = require(ReplicatedStorage.Shared.AttackDefinitions)
local ElementDefinitions = require(ReplicatedStorage.Shared.ElementDefinitions)
local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Network = require(ReplicatedStorage.Shared.Utility.Network)
local Signal = require(ReplicatedStorage.Shared.Utility.Signal)

local PlayerDataService: any = nil
local EconomyService: any = nil
local MonsterService: any = nil

local battleArenasFolder: Folder
local battle3DInstances: { [string]: { Folder: Folder, ModelA: Model, ModelB: Model } } = {}

local function getBattleArenasFolder(): Folder
	local folder = Workspace:FindFirstChild("ActiveBattleArenas") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ActiveBattleArenas"
		folder.Parent = Workspace
	end
	return folder
end

type InternalCombatant = {
	Player: Player?,
	IsBot: boolean,
	Name: string,
	Team: { Types.MonsterInstance },
	ActiveIndex: number,
	Status: Types.CombatantStatus,
	SubmittedAction: Types.CombatActionRequest?,
}

type BattleInstance = {
	Id: string,
	CombatantA: InternalCombatant,
	CombatantB: InternalCombatant,
	TurnNumber: number,
	State: "WaitingForActions" | "Resolving" | "Completed",
	TurnDeadline: number,
}

local activeBattles: { [string]: BattleInstance } = {}
local playerActiveBattle: { [Player]: string } = {}
-- Players currently being processed by PlayerRemoving: during that event `player.Parent`
-- is still `Players`, so this set lets `_finishBattle` skip them explicitly.
local departingPlayers: { [Player]: boolean } = {}

-- True if the player is still connected and can receive rewards / remotes / teleports.
local function isPlayerPresent(player: Player?): boolean
	return player ~= nil and player.Parent ~= nil and not departingPlayers[player]
end

local CombatService = {}

-- Fired for each human winner of a battle (bot practice included): (player, wasAgainstBot)
CombatService.BattleWonSignal = Signal.new() :: Signal.Signal<Player, boolean>
-- Fired for each human player once a battle (bot practice or PvP) has started: (player, battleId)
CombatService.BattleStartedSignal = Signal.new() :: Signal.Signal<Player, string>

local function createFreshStatus(): Types.CombatantStatus
	return {
		BurnTurns = 0,
		PoisonTurns = 0,
		ShieldTurns = 0,
		StunTurns = 0,
		SpeedBoostTurns = 0,
	}
end

local function cloneMonsterForBattle(m: Types.MonsterInstance): Types.MonsterInstance
	local clone = table.clone(m)
	clone.CurrentHealth = m.MaxHealth
	return clone
end

function CombatService:Init()
	Logger:Info("COMBAT", "Initializing CombatService...")
	PlayerDataService = require(script.Parent.PlayerDataService)
	EconomyService = require(script.Parent.EconomyService)
	MonsterService = require(script.Parent.MonsterService)
	battleArenasFolder = getBattleArenasFolder()

	-- Remotes
	Network.HandleFunction("SubmitBattleAction", function(player: Player, payload: any)
		if typeof(payload) ~= "table" then return false, "Invalid payload" end
		return self:SubmitAction(player, payload)
	end)

	Network.HandleFunction("StartBotBattle", function(player: Player)
		return self:StartPracticeBattle(player)
	end)
end

function CombatService:Start()
	-- A player leaving mid-battle forfeits it (issue #24)
	Players.PlayerRemoving:Connect(function(player: Player)
		departingPlayers[player] = true
		local ok, err = pcall(function()
			self:_handlePlayerLeft(player)
		end)
		if not ok then
			Logger:Error("COMBAT", "Failed to clean up battle for leaving player %s: %s", player.Name, tostring(err))
		end
		playerActiveBattle[player] = nil
		departingPlayers[player] = nil
	end)

	-- Main loop to monitor turn timeouts
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for battleId, battle in pairs(activeBattles) do
				if battle.State == "WaitingForActions" and now >= battle.TurnDeadline then
					Logger:Info("COMBAT", "Turn deadline reached for battle %s, resolving turn automatically", battleId)
					self:_resolveTurn(battle)
				end
			end
		end
	end)
end

-- True while the player is in a battle. A battle being set up stores the placeholder "" for
-- Player B in `playerActiveBattle`: it counts as "in battle" (the slot is already reserved).
function CombatService:IsInBattle(player: Player): boolean
	return playerActiveBattle[player] ~= nil
end

-- On success returns (true, battleId). On failure returns (false, reason, blamedPlayer) where
-- blamedPlayer is the player who prevented the battle (nil if unknown), so that matchmaking can
-- put the other one back in the queue (issue #31).
function CombatService:CreateBattle(playerA: Player, playerB: Player?, isBotPractice: boolean): (boolean, string?, Player?)
	local profileA = PlayerDataService:GetProfile(playerA)
	if not profileA then return false, "No profile for Player A", playerA end

	if self:IsInBattle(playerA) then
		return false, "Player A is already in an active battle", playerA
	end

	local teamA: { Types.MonsterInstance } = {}
	for _, uuid in ipairs(profileA.TeamMonsterUUIDs) do
		local m = profileA.Monsters[uuid]
		if m then
			table.insert(teamA, cloneMonsterForBattle(m))
		end
	end
	if #teamA == 0 then
		-- Fallback to first available monster
		for _, m in pairs(profileA.Monsters) do
			table.insert(teamA, cloneMonsterForBattle(m))
			break
		end
	end
	if #teamA == 0 then
		return false, "Player A has no monsters", playerA
	end

	local combatantB: InternalCombatant

	if isBotPractice or not playerB then
		-- Create a practice AI opponent
		local botSpecies = { "mossaur", "aquaphin", "zephlyn" }
		local chosenSpecies = botSpecies[math.random(1, #botSpecies)]
		local def = MonsterDefinitions.Get(chosenSpecies) :: Types.MonsterDefinition
		local calculatedStats, maxHealth = MonsterDefinitions.CalculateStats(chosenSpecies, 1, { Health=8, Attack=8, Defense=8, Speed=8 })

		local botMonster: Types.MonsterInstance = {
			UUID = HttpService:GenerateGUID(false),
			SpeciesId = chosenSpecies,
			Nickname = "Wild " .. def.DisplayName,
			Level = 1,
			XP = 0,
			CurrentHealth = maxHealth,
			MaxHealth = maxHealth,
			IVs = { Health=8, Attack=8, Defense=8, Speed=8 },
			CalculatedStats = calculatedStats,
			SkillsEquipped = table.clone(def.Skills),
			Parents = nil,
			Generation = 1,
			AssignedPlotId = nil,
			CreatedAt = os.time(),
		}

		combatantB = {
			Player = nil,
			IsBot = true,
			Name = "Trainer " .. def.DisplayName,
			Team = { botMonster },
			ActiveIndex = 1,
			Status = createFreshStatus(),
			SubmittedAction = nil,
		}
	else
		local profileB = PlayerDataService:GetProfile(playerB)
		if not profileB then return false, "No profile for Player B", playerB end

		if self:IsInBattle(playerB) then
			return false, "Player B is already in an active battle", playerB
		end

		local teamB: { Types.MonsterInstance } = {}
		for _, uuid in ipairs(profileB.TeamMonsterUUIDs) do
			local m = profileB.Monsters[uuid]
			if m then
				table.insert(teamB, cloneMonsterForBattle(m))
			end
		end
		if #teamB == 0 then
			for _, m in pairs(profileB.Monsters) do
				table.insert(teamB, cloneMonsterForBattle(m))
				break
			end
		end
		if #teamB == 0 then
			return false, "Player B has no monsters", playerB
		end

		combatantB = {
			Player = playerB,
			IsBot = false,
			Name = playerB.Name,
			Team = teamB,
			ActiveIndex = 1,
			Status = createFreshStatus(),
			SubmittedAction = nil,
		}
		playerActiveBattle[playerB] = "" -- placeholder
	end

	local combatantA: InternalCombatant = {
		Player = playerA,
		IsBot = false,
		Name = playerA.Name,
		Team = teamA,
		ActiveIndex = 1,
		Status = createFreshStatus(),
		SubmittedAction = nil,
	}

	local battleId = HttpService:GenerateGUID(false)
	local battle: BattleInstance = {
		Id = battleId,
		CombatantA = combatantA,
		CombatantB = combatantB,
		TurnNumber = 1,
		State = "WaitingForActions",
		TurnDeadline = os.time() + Config.COMBAT.TURN_TIMEOUT_SECONDS,
	}

	activeBattles[battleId] = battle
	playerActiveBattle[playerA] = battleId
	if playerB then
		playerActiveBattle[playerB] = battleId
	end

	Logger:Info("COMBAT", "Started battle %s (%s vs %s)", battleId, combatantA.Name, combatantB.Name)

	-- Spawn 3D physical monsters facing each other in the battle arena
	local posA = Vector3.new(-12, 4.2, -120)
	local posB = Vector3.new(12, 4.2, -120)

	local battleFolder = Instance.new("Folder")
	battleFolder.Name = "Battle_" .. battleId
	battleFolder.Parent = battleArenasFolder

	local modelA = MonsterService:BuildBattleMonsterModel(combatantA.Team[combatantA.ActiveIndex])
	if modelA.PrimaryPart then
		modelA:SetPrimaryPartCFrame(CFrame.lookAt(posA, posB))
	end
	modelA.Parent = battleFolder

	local modelB = MonsterService:BuildBattleMonsterModel(combatantB.Team[combatantB.ActiveIndex])
	if modelB.PrimaryPart then
		modelB:SetPrimaryPartCFrame(CFrame.lookAt(posB, posA))
	end
	modelB.Parent = battleFolder

	battle3DInstances[battleId] = {
		Folder = battleFolder,
		ModelA = modelA,
		ModelB = modelB,
	}

	-- Teleport combatants to arena podiums
	if playerA and playerA.Character and playerA.Character:FindFirstChild("HumanoidRootPart") then
		local hrp = playerA.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		hrp.CFrame = CFrame.lookAt(Vector3.new(-18, 7.5, -120), Vector3.new(0, 4, -120))
	end

	if playerB and playerB.Character and playerB.Character:FindFirstChild("HumanoidRootPart") then
		local hrp = playerB.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		hrp.CFrame = CFrame.lookAt(Vector3.new(18, 7.5, -120), Vector3.new(0, 4, -120))
	end

	-- Notify player(s)
	local startPayload = {
		BattleId = battleId,
		TurnNumber = 1,
		TurnTimeout = Config.COMBAT.TURN_TIMEOUT_SECONDS,
		YourTeam = combatantA.Team,
		YourActiveIndex = 1,
		OpponentName = combatantB.Name,
		OpponentActiveMonster = combatantB.Team[1],
		OpponentTeamCount = #combatantB.Team,
		ArenaCenter = Vector3.new(0, 4, -120),
		YourMonsterPosition = posA,
		OpponentMonsterPosition = posB,
	}
	Network.FireClient("BattleStarted", playerA, startPayload)

	if playerB then
		local startPayloadB = {
			BattleId = battleId,
			TurnNumber = 1,
			TurnTimeout = Config.COMBAT.TURN_TIMEOUT_SECONDS,
			YourTeam = combatantB.Team,
			YourActiveIndex = 1,
			OpponentName = combatantA.Name,
			OpponentActiveMonster = combatantA.Team[1],
			OpponentTeamCount = #combatantA.Team,
			ArenaCenter = Vector3.new(0, 4, -120),
			YourMonsterPosition = posB,
			OpponentMonsterPosition = posA,
		}
		Network.FireClient("BattleStarted", playerB, startPayloadB)
	end

	-- Listeners (MatchmakingService) take the players out of the PvP queue: the server must not
	-- rely on the client leaving the queue before starting a practice battle (issue #31)
	CombatService.BattleStartedSignal:Fire(playerA, battleId)
	if playerB then
		CombatService.BattleStartedSignal:Fire(playerB, battleId)
	end

	return true, battleId
end

function CombatService:StartPracticeBattle(player: Player): (boolean, string?)
	local success, result = self:CreateBattle(player, nil, true)
	return success, result -- Do not forward the blamed player to the client
end

function CombatService:SubmitAction(player: Player, request: Types.CombatActionRequest): (boolean, string?)
	local battleId = playerActiveBattle[player]
	if not battleId then return false, "You are not in a battle" end

	local battle = activeBattles[battleId]
	if not battle or battle.State ~= "WaitingForActions" then
		return false, "Battle is not accepting actions"
	end

	local combatant = (battle.CombatantA.Player == player) and battle.CombatantA or battle.CombatantB
	combatant.SubmittedAction = request

	Logger:Info("COMBAT", "Player %s submitted action: %s for battle %s", player.Name, request.Type, battleId)

	-- If Bot is opponent, generate bot action
	if battle.CombatantB.IsBot and not battle.CombatantB.SubmittedAction then
		local botActive = battle.CombatantB.Team[battle.CombatantB.ActiveIndex]
		local botSkill = botActive.SkillsEquipped[math.random(1, #botActive.SkillsEquipped)]
		battle.CombatantB.SubmittedAction = {
			Type = "Skill",
			SkillId = botSkill,
		}
	end

	-- If both have submitted, resolve the turn immediately!
	if battle.CombatantA.SubmittedAction and battle.CombatantB.SubmittedAction then
		self:_resolveTurn(battle)
	end

	return true, nil
end

function CombatService:_resolveTurn(battle: BattleInstance)
	battle.State = "Resolving"
	local a = battle.CombatantA
	local b = battle.CombatantB

	-- Default to first skill if player timed out
	if not a.SubmittedAction then
		local activeM = a.Team[a.ActiveIndex]
		a.SubmittedAction = { Type = "Skill", SkillId = activeM.SkillsEquipped[1] }
	end
	if not b.SubmittedAction then
		local activeM = b.Team[b.ActiveIndex]
		b.SubmittedAction = { Type = "Skill", SkillId = activeM.SkillsEquipped[1] }
	end

	local actionsToResolve = {
		{ Combatant = a, Opponent = b, Action = a.SubmittedAction },
		{ Combatant = b, Opponent = a, Action = b.SubmittedAction },
	}

	-- Calculate priority & speed ordering
	local function getOrderScore(entry: any): number
		local priority = 0
		if entry.Action.Type == "Switch" then
			priority = 10
		elseif entry.Action.Type == "Skill" and entry.Action.SkillId then
			local skillDef = AttackDefinitions.Get(entry.Action.SkillId)
			priority = skillDef and skillDef.Priority or 0
		end

		local activeMonster = entry.Combatant.Team[entry.Combatant.ActiveIndex]
		return CombatMath.GetActionOrderScore(priority, activeMonster.CalculatedStats.Speed, entry.Combatant.Status.SpeedBoostTurns > 0)
	end

	table.sort(actionsToResolve, function(x, y)
		local scoreX = getOrderScore(x)
		local scoreY = getOrderScore(y)
		if scoreX == scoreY then
			return math.random() > 0.5
		end
		return scoreX > scoreY
	end)

	local turnActionsReport: { Types.TurnActionResult } = {}

	for _, entry in ipairs(actionsToResolve) do
		local actor = entry.Combatant
		local defender = entry.Opponent
		local action = entry.Action
		local activeActorMonster = actor.Team[actor.ActiveIndex]
		local activeDefMonster = defender.Team[defender.ActiveIndex]

		if activeActorMonster.CurrentHealth <= 0 then
			-- Already knocked out, cannot act
			continue
		end

		if actor.Status.StunTurns > 0 then
			actor.Status.StunTurns -= 1
			table.insert(turnActionsReport, {
				ActorUUID = activeActorMonster.UUID,
				ActionType = "Pass",
				SkillName = "Stunned!",
				TargetUUID = activeActorMonster.UUID,
				DamageDealt = 0,
				IsCritical = false,
				ElementMultiplier = 1.0,
				TargetRemainingHealth = activeActorMonster.CurrentHealth,
				TargetDefeated = false,
				StatusApplied = "Stunned",
			})
			continue
		end

		if action.Type == "Skill" and action.SkillId then
			local skillDef = AttackDefinitions.Get(action.SkillId)
			if skillDef then
				-- Accuracy check
				local rollAcc = math.random(1, 100)
				if rollAcc <= skillDef.Accuracy then
					if skillDef.EffectType == "Shield" then
						actor.Status.ShieldTurns = skillDef.EffectDuration or 1
						table.insert(turnActionsReport, {
							ActorUUID = activeActorMonster.UUID,
							ActionType = "Skill",
							SkillName = skillDef.DisplayName,
							TargetUUID = activeActorMonster.UUID,
							DamageDealt = 0,
							IsCritical = false,
							ElementMultiplier = 1.0,
							TargetRemainingHealth = activeActorMonster.CurrentHealth,
							TargetDefeated = false,
							StatusApplied = "Shield",
						})
					elseif skillDef.EffectType == "SpeedBoost" then
						actor.Status.SpeedBoostTurns = skillDef.EffectDuration or 2
						table.insert(turnActionsReport, {
							ActorUUID = activeActorMonster.UUID,
							ActionType = "Skill",
							SkillName = skillDef.DisplayName,
							TargetUUID = activeActorMonster.UUID,
							DamageDealt = 0,
							IsCritical = false,
							ElementMultiplier = 1.0,
							TargetRemainingHealth = activeActorMonster.CurrentHealth,
							TargetDefeated = false,
							StatusApplied = "SpeedBoost",
						})
					else
						-- Attack Damage Calculation
						local actorDef = MonsterDefinitions.Get(activeActorMonster.SpeciesId)
						local targetDef = MonsterDefinitions.Get(activeDefMonster.SpeciesId)

						local baseDmg = CombatMath.ComputeBaseDamage(
							activeActorMonster.Level,
							skillDef.Power,
							activeActorMonster.CalculatedStats.Attack,
							activeDefMonster.CalculatedStats.Defense
						)

						-- Elemental effectiveness
						local primaryElem = (targetDef and targetDef.Elements[1]) or "Fire"
						local elemMultiplier = ElementDefinitions.GetEffectiveness(skillDef.Element, primaryElem)

						-- Critical hit & variance
						local isCrit = CombatMath.RollIsCritical(math.random)
						local variance = CombatMath.RollVariance(math.random)

						local finalDamage = CombatMath.ComputeFinalDamage(baseDmg, elemMultiplier, isCrit, variance, defender.Status.ShieldTurns > 0)
						activeDefMonster.CurrentHealth = CombatMath.ApplyDamage(activeDefMonster.CurrentHealth, finalDamage, activeDefMonster.MaxHealth)

						local targetKO = (activeDefMonster.CurrentHealth <= 0)
						local statusApplied: string? = nil

						if skillDef.EffectType == "Burn" and skillDef.EffectChance and math.random(1, 100) <= skillDef.EffectChance then
							defender.Status.BurnTurns = skillDef.EffectDuration or 3
							statusApplied = "Burn"
						end

						table.insert(turnActionsReport, {
							ActorUUID = activeActorMonster.UUID,
							ActionType = "Skill",
							SkillName = skillDef.DisplayName,
							TargetUUID = activeDefMonster.UUID,
							DamageDealt = finalDamage,
							IsCritical = isCrit,
							ElementMultiplier = elemMultiplier,
							TargetRemainingHealth = activeDefMonster.CurrentHealth,
							TargetDefeated = targetKO,
							StatusApplied = statusApplied,
						})
					end
				else
					-- Missed!
					table.insert(turnActionsReport, {
						ActorUUID = activeActorMonster.UUID,
						ActionType = "Skill",
						SkillName = skillDef.DisplayName .. " (Missed!)",
						TargetUUID = activeDefMonster.UUID,
						DamageDealt = 0,
						IsCritical = false,
						ElementMultiplier = 1.0,
						TargetRemainingHealth = activeDefMonster.CurrentHealth,
						TargetDefeated = false,
						StatusApplied = nil,
					})
				end
			end
		end
	end

	-- Apply end-of-turn status damage (Burn)
	for _, c in ipairs({ a, b }) do
		local activeM = c.Team[c.ActiveIndex]
		if activeM.CurrentHealth > 0 and c.Status.BurnTurns > 0 then
			c.Status.BurnTurns -= 1
			local burnDamage = CombatMath.ComputeBurnDamage(activeM.MaxHealth)
			activeM.CurrentHealth = CombatMath.ApplyDamage(activeM.CurrentHealth, burnDamage, activeM.MaxHealth)
		end
		if c.Status.ShieldTurns > 0 then c.Status.ShieldTurns -= 1 end
		if c.Status.SpeedBoostTurns > 0 then c.Status.SpeedBoostTurns -= 1 end
	end

	-- Auto-switch knocked out monsters to next alive monster
	for _, c in ipairs({ a, b }) do
		local activeM = c.Team[c.ActiveIndex]
		if activeM.CurrentHealth <= 0 then
			for idx, m in ipairs(c.Team) do
				if m.CurrentHealth > 0 then
					c.ActiveIndex = idx
					break
				end
			end
		end
	end

	-- Check Victory / Defeat conditions
	local aAlive = false
	for _, m in ipairs(a.Team) do if m.CurrentHealth > 0 then aAlive = true; break end end

	local bAlive = false
	for _, m in ipairs(b.Team) do if m.CurrentHealth > 0 then bAlive = true; break end end

	local winnerId: number? = nil
	local battleOver = false

	if not aAlive or not bAlive then
		battleOver = true
		if aAlive and not bAlive then
			winnerId = a.Player and a.Player.UserId or -1
		elseif bAlive and not aAlive then
			winnerId = b.Player and b.Player.UserId or -2
		end
	end

	local report: Types.TurnReport = {
		TurnNumber = battle.TurnNumber,
		Actions = turnActionsReport,
		ActiveMonsterUUID_PlayerA = a.Team[a.ActiveIndex].UUID,
		ActiveMonsterUUID_PlayerB = b.Team[b.ActiveIndex].UUID,
		WinnerPlayerUserId = winnerId,
	}

	-- Broadcast turn report
	if a.Player then Network.FireClient("BattleTurnReport", a.Player, report) end
	if b.Player then Network.FireClient("BattleTurnReport", b.Player, report) end

	if battleOver then
		self:_finishBattle(battle, winnerId)
	else
		-- Prepare next turn
		battle.TurnNumber += 1
		battle.State = "WaitingForActions"
		battle.TurnDeadline = os.time() + Config.COMBAT.TURN_TIMEOUT_SECONDS
		a.SubmittedAction = nil
		b.SubmittedAction = nil
	end
end

-- Called on PlayerRemoving: the leaving player forfeits any battle they are in.
-- PvP: the remaining opponent wins with the normal victory reward.
-- Bot practice: the battle is simply cleaned up (no winner, no reward).
function CombatService:_handlePlayerLeft(player: Player)
	local battleId = playerActiveBattle[player]
	if not battleId then return end

	local battle = activeBattles[battleId]
	if not battle or battle.State == "Completed" then
		return
	end

	local opponent = (battle.CombatantA.Player == player) and battle.CombatantB or battle.CombatantA
	local opponentPlayer = opponent.Player
	local winnerUserId: number? = nil
	if not opponent.IsBot and opponentPlayer and isPlayerPresent(opponentPlayer) then
		winnerUserId = opponentPlayer.UserId
	end

	Logger:Info("COMBAT", "Player %s left during battle %s, forfeiting (opponent: %s)", player.Name, battleId, opponent.Name)
	self:_finishBattle(battle, winnerUserId, true)
end

function CombatService:_finishBattle(battle: BattleInstance, winnerUserId: number?, byForfeit: boolean?)
	if battle.State == "Completed" then
		return -- Already finished (e.g. turn resolution and forfeit racing)
	end
	battle.State = "Completed"
	local a = battle.CombatantA
	local b = battle.CombatantB

	local isAWinner = (winnerUserId ~= nil and a.Player ~= nil and winnerUserId == a.Player.UserId)
	local isBWinner = (winnerUserId ~= nil and b.Player ~= nil and winnerUserId == b.Player.UserId)

	-- Distribute rewards (only to players still connected: a leaver gets nothing)
	if a.Player then
		if isPlayerPresent(a.Player) then
			local reward = isAWinner and Config.COMBAT.VICTORY_REWARDS or Config.COMBAT.DEFEAT_REWARDS
			EconomyService:AddCoins(a.Player, reward.Coins, isAWinner and "PvP Battle Victory" or "PvP Battle Consolation")
			PlayerDataService:AddPlayerXP(a.Player, reward.XP, isAWinner and "Battle Victory" or "Battle Defeat")
			Network.FireClient("BattleEnded", a.Player, {
				Victory = isAWinner,
				CoinsGained = reward.Coins,
				XPGained = reward.XP,
				OpponentLeft = byForfeit == true,
			})
		end
		playerActiveBattle[a.Player] = nil
	end

	if b.Player then
		if isPlayerPresent(b.Player) then
			local reward = isBWinner and Config.COMBAT.VICTORY_REWARDS or Config.COMBAT.DEFEAT_REWARDS
			EconomyService:AddCoins(b.Player, reward.Coins, isBWinner and "PvP Battle Victory" or "PvP Battle Consolation")
			PlayerDataService:AddPlayerXP(b.Player, reward.XP, isBWinner and "Battle Victory" or "Battle Defeat")
			Network.FireClient("BattleEnded", b.Player, {
				Victory = isBWinner,
				CoinsGained = reward.Coins,
				XPGained = reward.XP,
				OpponentLeft = byForfeit == true,
			})
		end
		playerActiveBattle[b.Player] = nil
	end

	-- Notify listeners (e.g. QuestService) of human victories
	if isAWinner and a.Player and isPlayerPresent(a.Player) then CombatService.BattleWonSignal:Fire(a.Player, b.IsBot) end
	if isBWinner and b.Player and isPlayerPresent(b.Player) then CombatService.BattleWonSignal:Fire(b.Player, a.IsBot) end

	activeBattles[battle.Id] = nil

	-- Destroy 3D arena monsters
	local battle3D = battle3DInstances[battle.Id]
	if battle3D then
		if battle3D.Folder then battle3D.Folder:Destroy() end
		battle3DInstances[battle.Id] = nil
	end

	-- Teleport players back to village spawn after short fanfare
	task.delay(3.5, function()
		if a.Player and a.Player.Parent ~= nil and a.Player.Character and a.Player.Character:FindFirstChild("HumanoidRootPart") then
			local hrp = a.Player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
			hrp.CFrame = CFrame.new(0, 4, 0)
		end
		if b.Player and b.Player.Parent ~= nil and b.Player.Character and b.Player.Character:FindFirstChild("HumanoidRootPart") then
			local hrp = b.Player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
			hrp.CFrame = CFrame.new(0, 4, 0)
		end
	end)

	Logger:Info("COMBAT", "Battle %s ended%s. Winner User ID: %s", battle.Id, byForfeit and " by forfeit" or "", tostring(winnerUserId))
end

return CombatService
