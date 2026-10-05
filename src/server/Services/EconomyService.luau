--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)

local PlayerDataService: any = nil

local EconomyService = {}

local function isValidAmount(amount: any): boolean
	if typeof(amount) ~= "number" then return false end
	if amount <= 0 then return false end
	if amount ~= amount then return false end -- NaN check
	if amount == math.huge or amount == -math.huge then return false end
	return true
end

function EconomyService:Init()
	Logger:Info("ECONOMY", "Initializing EconomyService...")
	PlayerDataService = require(script.Parent.PlayerDataService)

	Network.HandleFunction("GetBalance", function(player: Player)
		return {
			Coins = self:GetCoins(player),
			Gems = self:GetGems(player),
		}
	end)
end

function EconomyService:Start()
	-- Ready
end

function EconomyService:GetCoins(player: Player): number
	local profile = PlayerDataService:GetProfile(player)
	return profile and profile.Currency.Coins or 0
end

function EconomyService:GetGems(player: Player): number
	local profile = PlayerDataService:GetProfile(player)
	return profile and profile.Currency.Gems or 0
end

function EconomyService:AddCoins(player: Player, amount: number, reason: string): boolean
	if not isValidAmount(amount) then
		Logger:Warn("ECONOMY", "Player %s attempted to add invalid coin amount: %s", player.Name, tostring(amount))
		return false
	end

	local cleanAmount = math.floor(amount)
	local success = PlayerDataService:UpdateProfile(player, function(profile)
		profile.Currency.Coins += cleanAmount
	end)

	if success then
		Logger:Info("ECONOMY", "Added %d coins to %s (Reason: %s, New total: %d)", cleanAmount, player.Name, reason, self:GetCoins(player))
		Network.FireClient("CurrencyChanged", player, {
			Currency = "Coins",
			Amount = cleanAmount,
			Total = self:GetCoins(player),
			Reason = reason,
		})
	end

	return success
end

function EconomyService:DeductCoins(player: Player, amount: number, reason: string): boolean
	if not isValidAmount(amount) then
		Logger:Warn("ECONOMY", "Player %s attempted to deduct invalid coin amount: %s", player.Name, tostring(amount))
		return false
	end

	local cleanAmount = math.floor(amount)
	local currentBalance = self:GetCoins(player)

	if currentBalance < cleanAmount then
		Logger:Warn("ECONOMY", "Player %s has insufficient coins (%d < %d) for %s", player.Name, currentBalance, cleanAmount, reason)
		return false
	end

	local success = PlayerDataService:UpdateProfile(player, function(profile)
		if profile.Currency.Coins >= cleanAmount then
			profile.Currency.Coins -= cleanAmount
		else
			error("Balance race condition prevented")
		end
	end)

	if success then
		Logger:Info("ECONOMY", "Deducted %d coins from %s (Reason: %s, Remaining: %d)", cleanAmount, player.Name, reason, self:GetCoins(player))
		Network.FireClient("CurrencyChanged", player, {
			Currency = "Coins",
			Amount = -cleanAmount,
			Total = self:GetCoins(player),
			Reason = reason,
		})
	end

	return success
end

function EconomyService:AddGems(player: Player, amount: number, reason: string): boolean
	if not isValidAmount(amount) then
		return false
	end

	local cleanAmount = math.floor(amount)
	local success = PlayerDataService:UpdateProfile(player, function(profile)
		profile.Currency.Gems += cleanAmount
	end)

	if success then
		Logger:Info("ECONOMY", "Added %d gems to %s (Reason: %s, New total: %d)", cleanAmount, player.Name, reason, self:GetGems(player))
		Network.FireClient("CurrencyChanged", player, {
			Currency = "Gems",
			Amount = cleanAmount,
			Total = self:GetGems(player),
			Reason = reason,
		})
	end

	return success
end

function EconomyService:DeductGems(player: Player, amount: number, reason: string): boolean
	if not isValidAmount(amount) then
		return false
	end

	local cleanAmount = math.floor(amount)
	local currentBalance = self:GetGems(player)

	if currentBalance < cleanAmount then
		return false
	end

	local success = PlayerDataService:UpdateProfile(player, function(profile)
		if profile.Currency.Gems >= cleanAmount then
			profile.Currency.Gems -= cleanAmount
		else
			error("Gem balance race condition prevented")
		end
	end)

	if success then
		Logger:Info("ECONOMY", "Deducted %d gems from %s (Reason: %s, Remaining: %d)", cleanAmount, player.Name, reason, self:GetGems(player))
		Network.FireClient("CurrencyChanged", player, {
			Currency = "Gems",
			Amount = -cleanAmount,
			Total = self:GetGems(player),
			Reason = reason,
		})
	end

	return success
end

return EconomyService
