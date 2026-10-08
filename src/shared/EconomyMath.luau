--!strict
-- Pure currency validation rules (no Roblox services, no side effects).
-- Used by EconomyService and exercised directly by tests/run_tests.luau.

local EconomyMath = {}

-- A currency amount is valid when it is a finite, strictly positive number (rejects NaN and ±inf).
function EconomyMath.IsValidAmount(amount: any): boolean
	if typeof(amount) ~= "number" then return false end
	if amount ~= amount then return false end -- NaN check
	if amount <= 0 then return false end
	if amount == math.huge then return false end
	return true
end

return EconomyMath
