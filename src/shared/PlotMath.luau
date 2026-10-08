--!strict
-- Pure plot / decoration placement rules (no Roblox services, no side effects).
-- Used by PlotService and exercised directly by tests/run_tests.luau.
local Config = require(script.Parent.Config)

local PlotMath = {}

PlotMath.DECORATION_EDGE_MARGIN = 2 -- Studs kept free between a decoration and the plot border

-- Snaps a plot-local (X, Z) position to the decoration grid, then clamps it inside the plot
-- (minus DECORATION_EDGE_MARGIN). `plotSize` only needs X and Z (a Vector3 in game).
function PlotMath.SnapDecorationPosition(
	localX: number,
	localZ: number,
	plotSize: { X: number, Z: number },
	gridSize: number?
): (number, number)
	local grid = gridSize or Config.PLOT_GRID_SIZE or 4
	local halfX = (plotSize.X / 2) - PlotMath.DECORATION_EDGE_MARGIN
	local halfZ = (plotSize.Z / 2) - PlotMath.DECORATION_EDGE_MARGIN

	local snappedX = math.clamp(math.round(localX / grid) * grid, -halfX, halfX)
	local snappedZ = math.clamp(math.round(localZ / grid) * grid, -halfZ, halfZ)
	return snappedX, snappedZ
end

return PlotMath
