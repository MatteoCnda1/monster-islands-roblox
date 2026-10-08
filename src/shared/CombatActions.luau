--!strict
-- Pure validation / helpers for battle actions sent by clients (issue #28).
-- No Roblox services, no side effects: used by CombatService and exercised directly by tests/run_tests.luau.
local Types = require(script.Parent.Types)

local CombatActions = {}

-- A switch always happens before any skill (skill priorities stay well below this value).
CombatActions.SWITCH_PRIORITY = 10

local VALID_TYPES: { [string]: boolean } = {
	Skill = true,
	Switch = true,
	Pass = true,
}

-- Index in `team` of the monster with this UUID, or nil.
function CombatActions.FindMonsterIndex(team: { Types.MonsterInstance }, uuid: string): number?
	for index, monster in ipairs(team) do
		if monster.UUID == uuid then
			return index
		end
	end
	return nil
end

-- Index of a valid switch target: a living team member that is not the active one. Nil otherwise.
function CombatActions.FindSwitchTargetIndex(team: { Types.MonsterInstance }, uuid: string, activeIndex: number): number?
	local index = CombatActions.FindMonsterIndex(team, uuid)
	if index == nil or index == activeIndex then
		return nil
	end
	if team[index].CurrentHealth <= 0 then
		return nil
	end
	return index
end

-- True if the team holds a living monster other than the active one (i.e. a switch is possible).
function CombatActions.CanSwitch(team: { Types.MonsterInstance }, activeIndex: number): boolean
	for index, monster in ipairs(team) do
		if index ~= activeIndex and monster.CurrentHealth > 0 then
			return true
		end
	end
	return false
end

-- Validates an untrusted action payload against the combatant's active monster and team.
-- Returns a sanitized copy holding only the fields relevant to its type (unexpected fields are
-- dropped), or nil and a reason.
function CombatActions.ValidateAction(
	action: any,
	activeMonster: Types.MonsterInstance?,
	team: { Types.MonsterInstance }
): (Types.CombatActionRequest?, string?)
	if typeof(action) ~= "table" then
		return nil, "Action must be a table"
	end
	if activeMonster == nil then
		return nil, "No active monster"
	end

	local actionType = action.Type
	if typeof(actionType) ~= "string" or not VALID_TYPES[actionType] then
		return nil, string.format("Invalid action type '%s'", tostring(actionType))
	end

	if actionType == "Skill" then
		local skillId = action.SkillId
		if typeof(skillId) ~= "string" then
			return nil, "SkillId must be a string"
		end
		if not table.find(activeMonster.SkillsEquipped, skillId) then
			return nil, string.format("Skill '%s' is not equipped by the active monster", skillId)
		end
		return { Type = "Skill", SkillId = skillId }, nil
	elseif actionType == "Switch" then
		local targetUUID = action.SwitchMonsterUUID
		if typeof(targetUUID) ~= "string" then
			return nil, "SwitchMonsterUUID must be a string"
		end
		if targetUUID == activeMonster.UUID then
			return nil, "Cannot switch to the active monster"
		end
		local index = CombatActions.FindMonsterIndex(team, targetUUID)
		if index == nil then
			return nil, "Switch target is not in your team"
		end
		if team[index].CurrentHealth <= 0 then
			return nil, "Switch target is knocked out"
		end
		return { Type = "Switch", SwitchMonsterUUID = targetUUID }, nil
	end

	return { Type = "Pass" }, nil
end

return CombatActions
