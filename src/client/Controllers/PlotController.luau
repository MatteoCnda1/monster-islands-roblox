--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local Network = require(ReplicatedStorage.Shared.Utility.Network)

local localPlayer = Players.LocalPlayer

local UIController: any = nil

-- Plot models of the local player's island that already have a purchase prompt
local boundPlotModels: { [Model]: boolean } = {}

local PlotController = {}

local function getPlotConfig(plotId: number): Types.PlotConfig?
	for _, plotConfig in ipairs(Config.PLOTS) do
		if plotConfig.Id == plotId then
			return plotConfig
		end
	end
	return nil
end

local function formatCost(plotConfig: Types.PlotConfig): string
	if plotConfig.CostGems > 0 then
		return string.format("%d Coins + %d Gems", plotConfig.CostCoins, plotConfig.CostGems)
	end
	return string.format("%d Coins", plotConfig.CostCoins)
end

local function notify(text: string, color: Color3)
	if UIController and typeof(UIController.ShowNotification) == "function" then
		UIController:ShowNotification(text, color)
	end
end

-- Purchase prompts are created locally, only on the local player's own plots, so other players
-- never see them. The purchase itself is validated by the server ("RequestPurchasePlot").
local function bindPurchasePrompt(plotModel: Model)
	if boundPlotModels[plotModel] then return end

	local plotId = plotModel:GetAttribute("PlotId")
	if typeof(plotId) ~= "number" then return end
	local plotConfig = getPlotConfig(plotId)
	if not plotConfig then return end

	local podium = plotModel:WaitForChild("SignPodium", 10)
	if not podium or boundPlotModels[plotModel] or not plotModel.Parent then return end
	boundPlotModels[plotModel] = true

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlotPurchasePrompt"
	prompt.ActionText = string.format("Unlock (%s)", formatCost(plotConfig))
	prompt.ObjectText = plotConfig.Name
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.Enabled = plotModel:GetAttribute("IsUnlocked") ~= true
	prompt.Parent = podium

	local connections: { RBXScriptConnection } = {}

	table.insert(connections, plotModel:GetAttributeChangedSignal("IsUnlocked"):Connect(function()
		prompt.Enabled = plotModel:GetAttribute("IsUnlocked") ~= true
	end))

	local purchasing = false
	table.insert(connections, prompt.Triggered:Connect(function()
		if purchasing then return end
		purchasing = true
		local ok, success, err = pcall(Network.InvokeServer, "RequestPurchasePlot", plotId)
		purchasing = false
		-- Success is notified through the "PlotPurchased" event (UIController)
		if not ok or not success then
			local reason = if ok then tostring(err or "Purchase failed") else "Purchase failed"
			Logger:Info("PLOT", "Purchase of plot %d failed: %s", plotId, reason)
			notify(reason, Color3.fromRGB(220, 80, 80))
		end
	end))

	-- Model destroyed (owner left) or podium streamed out: unbind so it can be bound again
	local function unbindIfGone()
		if plotModel:IsDescendantOf(Workspace) and podium:IsDescendantOf(plotModel) then return end
		boundPlotModels[plotModel] = nil
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		prompt:Destroy()
	end
	table.insert(connections, plotModel.AncestryChanged:Connect(unbindIfGone))
	table.insert(connections, podium.AncestryChanged:Connect(unbindIfGone))
end

local function watchSlotFolder(slotFolder: Instance)
	if slotFolder:GetAttribute("OwnerUserId") ~= localPlayer.UserId then return end

	local function onChild(child: Instance)
		if child:IsA("Model") and child:GetAttribute("PlotId") ~= nil then
			local plotModel = child :: Model
			task.spawn(bindPurchasePrompt, plotModel)
			-- A podium streamed back in comes as a new instance: bind it again
			plotModel.ChildAdded:Connect(function(grandChild)
				if grandChild.Name == "SignPodium" then
					task.spawn(bindPurchasePrompt, plotModel)
				end
			end)
		end
	end

	slotFolder.ChildAdded:Connect(onChild)
	for _, child in ipairs(slotFolder:GetChildren()) do
		onChild(child)
	end
end

function PlotController:Init()
	Logger:Info("PLOT", "Initializing PlotController...")
	UIController = require(script.Parent.UIController)

	Network.OnClientEvent("DecorationPlaced", function(data: any)
		Logger:Info("PLOT", "Decoration placed: %s on Plot %s", data.Decoration and data.Decoration.DecorationId or "?", tostring(data.PlotId))
	end)

	Network.OnClientEvent("PlotSlotAssigned", function(data: Types.PlotSlotAssignment)
		if data.SlotIndex then
			Logger:Info("PLOT", "Assigned to island %d/%d", data.SlotIndex, data.MaxSlots)
			notify(string.format("Welcome to your island (#%d)! A bridge links it to the village.", data.SlotIndex), Color3.fromRGB(80, 200, 120))
		else
			Logger:Warn("PLOT", "Every island of this server is taken (%d)", data.MaxSlots)
			notify("All islands are taken: yours will appear when one frees up", Color3.fromRGB(220, 150, 60))
		end
	end)
end

function PlotController:Start()
	-- Bind purchase prompts on the local player's island (Workspace.Plots.Slot_<n>)
	task.spawn(function()
		local plotsFolder = Workspace:WaitForChild("Plots", 30)
		if not plotsFolder then
			Logger:Warn("PLOT", "Workspace.Plots not found, plot purchase prompts disabled")
			return
		end
		plotsFolder.ChildAdded:Connect(watchSlotFolder)
		for _, slotFolder in ipairs(plotsFolder:GetChildren()) do
			watchSlotFolder(slotFolder)
		end
	end)

	-- Request server to refresh plot visual state and active breeding eggs for this client
	task.wait(1)
	Network.FireServer("RefreshPlotsRequest")
	Network.FireServer("RefreshBreedingEggs")
end

return PlotController
