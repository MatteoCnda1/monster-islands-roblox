--!strict
-- Shared Type Definitions for Monster Islands

export type ElementType = "Fire" | "Water" | "Earth" | "Wind" | "Nature" | "Shadow" | "Light" | "Arcane"

export type RarityType = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

export type Stats = {
	Health: number,
	Attack: number,
	Defense: number,
	Speed: number,
}

export type StatGrowth = {
	Health: number,
	Attack: number,
	Defense: number,
	Speed: number,
}

export type BreedingConfig = {
	CompatibleElements: { ElementType },
	BreedingTime: number, -- Duration in seconds
	IncubationTime: number, -- Duration in seconds
}

export type AttackDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	Element: ElementType,
	Power: number,
	Accuracy: number, -- 0 to 100
	Priority: number, -- Default 0, higher goes first
	CooldownTurns: number,
	EffectType: ("Damage" | "Heal" | "Shield" | "Burn" | "Stun" | "SpeedBoost")?,
	EffectChance: number?, -- 0 to 100
	EffectDuration: number?, -- in turns
}

export type MonsterDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	Rarity: RarityType,
	Elements: { ElementType },
	BaseStats: Stats,
	Growth: StatGrowth,
	Breeding: BreedingConfig,
	Skills: { string },
	PrimaryColor: Color3,
	SecondaryColor: Color3,
	ScaleMultiplier: number,
}

export type MonsterIVs = {
	Health: number, -- 0 to 15
	Attack: number,
	Defense: number,
	Speed: number,
}

export type MonsterInstance = {
	UUID: string,
	SpeciesId: string,
	Nickname: string?,
	Level: number,
	XP: number,
	CurrentHealth: number,
	MaxHealth: number,
	IVs: MonsterIVs,
	CalculatedStats: Stats,
	SkillsEquipped: { string },
	Parents: { string }?, -- [ParentUUID_A, ParentUUID_B]
	Generation: number,
	AssignedPlotId: number?,
	CreatedAt: number,
}

export type PlotConfig = {
	Id: number,
	Name: string,
	CostCoins: number,
	CostGems: number,
	RequiredLevel: number,
	Size: Vector3,
	LocalPosition: Vector3, -- Relative to the owner's island slot origin (see PlotSlots)
	MaxMonstersCapacity: number,
}

-- Payload of the "PlotSlotAssigned" server -> client event (per-player plot islands, issue #21)
export type PlotSlotAssignment = {
	SlotIndex: number?, -- nil when every island of the server is taken
	Origin: Vector3?,
	MaxSlots: number,
}

export type PlacedDecoration = {
	UUID: string,
	DecorationId: string,
	PositionX: number,
	PositionY: number,
	PositionZ: number,
	RotationY: number,
	PlacedAt: number,
}

export type DecorationConfig = {
	Id: string,
	Name: string,
	CostCoins: number,
	Size: Vector3,
	PrimaryColor: Color3,
	SecondaryColor: Color3,
}

export type PlotData = {
	Id: number,
	IsUnlocked: boolean,
	UnlockedAt: number?,
	PlacedMonsters: { string }, -- List of Monster UUIDs
	PlacedDecorations: { PlacedDecoration },
}

export type CurrencyData = {
	Coins: number,
	Gems: number,
}

export type ProgressionData = {
	Level: number,
	XP: number,
}

export type QuestDefinition = {
	Id: string,
	Title: string,
	Description: string,
	RewardCoins: number,
	RewardGems: number,
	RewardXP: number,
}

-- Quest definition enriched with the completion state of a given player (GetActiveQuests payload)
export type QuestStatus = {
	Id: string,
	Title: string,
	Description: string,
	RewardCoins: number,
	RewardGems: number,
	RewardXP: number,
	IsCompleted: boolean,
	CompletedAt: number?,
}

export type BreedingSession = {
	Id: string,
	ParentA_UUID: string,
	ParentB_UUID: string,
	StartedAt: number,
	DurationSeconds: number,
	EggReadyAt: number,
	EggSpeciesId: string,
	EggIVs: MonsterIVs,
	IsCompleted: boolean,
	IsHatched: boolean,
}

export type PlayerData = {
	Version: number,
	Currency: CurrencyData,
	Progression: ProgressionData,
	Monsters: { [string]: MonsterInstance },
	TeamMonsterUUIDs: { string }, -- Active team for PvP/PvE (up to 3)
	Plots: { [string]: PlotData }, -- Keyed by tostring(PlotId)
	BreedingSessions: { [string]: BreedingSession },
	Inventory: { [string]: number },
	CompletedQuests: { [string]: number }, -- QuestId -> os.time() of completion
	LastSaveTimestamp: number,
}

-- Combat Types
export type CombatActionType = "Skill" | "Switch" | "Pass"

export type CombatActionRequest = {
	Type: CombatActionType,
	SkillId: string?,
	TargetUUID: string?,
	SwitchMonsterUUID: string?,
}

export type CombatantStatus = {
	BurnTurns: number,
	PoisonTurns: number,
	ShieldTurns: number,
	StunTurns: number,
	SpeedBoostTurns: number,
}

export type Combatant = {
	Player: Player?,
	Team: { MonsterInstance },
	ActiveIndex: number,
	ActiveStatus: CombatantStatus,
}

export type TurnActionResult = {
	ActorUUID: string,
	ActionType: CombatActionType,
	SkillName: string?,
	TargetUUID: string?,
	DamageDealt: number,
	IsCritical: boolean,
	ElementMultiplier: number,
	TargetRemainingHealth: number,
	TargetDefeated: boolean,
	StatusApplied: string?,
	-- ActionType "Switch" only: ActorUUID = monster leaving, TargetUUID = monster entering,
	-- SwitchedInMonster = snapshot of the entering monster (so the opponent can display it).
	SwitchedInMonster: MonsterInstance?,
}

export type TurnReport = {
	TurnNumber: number,
	Actions: { TurnActionResult },
	ActiveMonsterUUID_PlayerA: string,
	ActiveMonsterUUID_PlayerB: string,
	WinnerPlayerUserId: number?, -- nil if battle continues
	MonsterHealth: { [string]: number }?, -- UUID -> CurrentHealth of every monster of both teams at end of turn
}

local Types = {}
return Types
