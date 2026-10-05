--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)

local PlayerDataService: any = nil

local InventoryService = {}

function InventoryService:Init()
	Logger:Info("INVENTORY", "Initializing InventoryService...")
	PlayerDataService = require(script.Parent.PlayerDataService)

	Network.HandleFunction("GetInventory", function(player: Player)
		local profile = PlayerDataService:GetProfile(player)
		return profile and profile.Inventory or {}
	end)
end

function InventoryService:Start()
	-- Ready
end

function InventoryService:AddItem(player: Player, itemId: string, count: number): boolean
	if count <= 0 then return false end
	local cleanCount = math.floor(count)

	local success = PlayerDataService:UpdateProfile(player, function(profile)
		local current = profile.Inventory[itemId] or 0
		profile.Inventory[itemId] = current + cleanCount
	end)

	if success then
		Logger:Info("INVENTORY", "Added %dx %s to %s", cleanCount, itemId, player.Name)
		Network.FireClient("InventoryChanged", player, {
			ItemId = itemId,
			Delta = cleanCount,
			Total = self:GetItemCount(player, itemId),
		})
	end
	return success
end

function InventoryService:RemoveItem(player: Player, itemId: string, count: number): boolean
	if count <= 0 then return false end
	local cleanCount = math.floor(count)
	local currentCount = self:GetItemCount(player, itemId)

	if currentCount < cleanCount then
		return false
	end

	local success = PlayerDataService:UpdateProfile(player, function(profile)
		local current = profile.Inventory[itemId] or 0
		if current >= cleanCount then
			local newCount = current - cleanCount
			if newCount <= 0 then
				profile.Inventory[itemId] = nil
			else
				profile.Inventory[itemId] = newCount
			end
		else
			error("Inventory deduction race condition")
		end
	end)

	if success then
		Logger:Info("INVENTORY", "Removed %dx %s from %s", cleanCount, itemId, player.Name)
		Network.FireClient("InventoryChanged", player, {
			ItemId = itemId,
			Delta = -cleanCount,
			Total = self:GetItemCount(player, itemId),
		})
	end
	return success
end

function InventoryService:GetItemCount(player: Player, itemId: string): number
	local profile = PlayerDataService:GetProfile(player)
	return profile and profile.Inventory[itemId] or 0
end

function InventoryService:HasItem(player: Player, itemId: string, count: number?): boolean
	local needed = count or 1
	return self:GetItemCount(player, itemId) >= needed
end

return InventoryService
