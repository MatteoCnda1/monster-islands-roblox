--!strict
-- PlotSlots: pure geometry & allocation helpers for per-player plot islands (issue #21).
-- Slot N is an annex island placed on a ring around the hub; Config.PLOTS[].LocalPosition is
-- relative to the slot origin. No Roblox service is used here (only Vector3 + Config), so these
-- functions can be unit-tested with a minimal Vector3 mock.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local PlotSlots = {}

function PlotSlots.GetSlotCount(): number
	return Config.PLOT_SLOTS.MAX_SLOTS
end

function PlotSlots.IsValidSlot(slotIndex: number): boolean
	return slotIndex >= 1 and slotIndex <= PlotSlots.GetSlotCount() and slotIndex == math.floor(slotIndex)
end

-- Unit vector (y = 0) pointing from the hub center towards the slot's island
function PlotSlots.GetDirection(slotIndex: number): Vector3
	local slotConfig = Config.PLOT_SLOTS
	local angle = math.rad(slotConfig.RING_ANGLE_OFFSET_DEGREES + (slotIndex - 1) * (360 / slotConfig.MAX_SLOTS))
	return Vector3.new(math.sin(angle), 0, -math.cos(angle))
end

-- Island center at ground level (y = 0, same as the hub island base)
function PlotSlots.GetOrigin(slotIndex: number): Vector3
	local direction = PlotSlots.GetDirection(slotIndex)
	local radius = Config.PLOT_SLOTS.RING_RADIUS
	return Vector3.new(direction.X * radius, 0, direction.Z * radius)
end

function PlotSlots.ToWorldPosition(slotIndex: number, localPosition: Vector3): Vector3
	local origin = PlotSlots.GetOrigin(slotIndex)
	return Vector3.new(origin.X + localPosition.X, origin.Y + localPosition.Y, origin.Z + localPosition.Z)
end

function PlotSlots.GetPlotWorldPosition(slotIndex: number, plotConfig: Types.PlotConfig): Vector3
	return PlotSlots.ToWorldPosition(slotIndex, plotConfig.LocalPosition)
end

-- Bridge from the village spawn to the edge of the slot's island (both points at y = 0).
-- The island is an axis-aligned box, so the edge distance depends on the bridge direction.
function PlotSlots.GetBridgeEndpoints(slotIndex: number): (Vector3, Vector3)
	local slotConfig = Config.PLOT_SLOTS
	local direction = PlotSlots.GetDirection(slotIndex)
	local halfX = slotConfig.ISLAND_SIZE.X / 2
	local halfZ = slotConfig.ISLAND_SIZE.Z / 2

	local edgeDistance = math.huge
	if math.abs(direction.X) > 1e-6 then
		edgeDistance = math.min(edgeDistance, halfX / math.abs(direction.X))
	end
	if math.abs(direction.Z) > 1e-6 then
		edgeDistance = math.min(edgeDistance, halfZ / math.abs(direction.Z))
	end

	local startRadius = slotConfig.BRIDGE_START_RADIUS
	local endRadius = slotConfig.RING_RADIUS - edgeDistance + 2 -- Overlap the island by 2 studs
	return Vector3.new(direction.X * startRadius, 0, direction.Z * startRadius),
		Vector3.new(direction.X * endRadius, 0, direction.Z * endRadius)
end

-- Lowest free slot index, or nil when all `maxSlots` slots are occupied
function PlotSlots.FindFreeSlot(occupied: { [number]: any }, maxSlots: number): number?
	for slotIndex = 1, maxSlots do
		if occupied[slotIndex] == nil then
			return slotIndex
		end
	end
	return nil
end

return PlotSlots
