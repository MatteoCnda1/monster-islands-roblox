--!strict
-- Pure PvP matchmaking rules (no Roblox services, no side effects).
-- Used by MatchmakingService and exercised directly by tests/run_tests.luau.
--
-- Once the two players at the head of the queue are paired, they are referred to by slot:
-- 1 = the one who waited the longest, 2 = the next one.

local MatchmakingRules = {}

export type PairResolution = {
	StartBattle: boolean, -- Both players are eligible: create the battle
	Requeue: { number }, -- Slots to put back at the head of the queue, in this order
	Dropped: { number }, -- Slots removed from the queue
}

local function split(eligible1: boolean, eligible2: boolean): ({ number }, { number })
	local requeue: { number } = {}
	local dropped: { number } = {}
	table.insert(if eligible1 then requeue else dropped, 1)
	table.insert(if eligible2 then requeue else dropped, 2)
	return requeue, dropped
end

-- Before creating the battle: a player is eligible if still connected and not already in a battle.
-- If only one of them is, they keep their place at the head of the queue instead of being penalised.
function MatchmakingRules.ResolvePair(eligible1: boolean, eligible2: boolean): PairResolution
	if eligible1 and eligible2 then
		return { StartBattle = true, Requeue = {}, Dropped = {} }
	end
	local requeue, dropped = split(eligible1, eligible2)
	return { StartBattle = false, Requeue = requeue, Dropped = dropped }
end

-- After CombatService:CreateBattle failed. `eligible1/2` are re-evaluated after the failure and
-- `blamedSlot` is the slot CreateBattle reported as the cause (nil if unknown). The blamed player is
-- dropped; the other one goes back to the head of the queue if still eligible.
-- If nobody can be blamed and both still look eligible, both are dropped: re-queuing them would
-- pair them again immediately and repeat the same failure forever.
function MatchmakingRules.ResolveFailedBattle(eligible1: boolean, eligible2: boolean, blamedSlot: number?): PairResolution
	if blamedSlot == 1 then
		eligible1 = false
	elseif blamedSlot == 2 then
		eligible2 = false
	end

	if eligible1 and eligible2 then
		return { StartBattle = false, Requeue = {}, Dropped = { 1, 2 } }
	end
	local requeue, dropped = split(eligible1, eligible2)
	return { StartBattle = false, Requeue = requeue, Dropped = dropped }
end

return MatchmakingRules
