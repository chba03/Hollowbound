--[[
	Finds the real ground under a point: the terrain surface, which is uneven and can sit
	well above a ledge's planned height. Used to sit relics, camp props, and camp rings on top of
	the ground instead of at the ledge's nominal height, where they clipped into it.
	Only terrain counts, so props, scaffolds, and characters never get in the way. A
	hand-built map with part floors gets nil and keeps its planned heights.
]]

local Ground = {}

-- Start well above the point: a ledge's real surface can sit several studs above its
-- planned height, and a ray that starts inside terrain never finds the surface. Ledges
-- are LayerHeight apart, so 30 studs up is still open air under the ledge above.
local SEARCH_UP = 30
local SEARCH_DOWN = 12

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { workspace.Terrain }
params.IgnoreWater = false

-- Returns the Y of the terrain surface at position's X/Z, searching from 30 studs above
-- to 12 below it, or nil (no terrain there: callers keep their planned height).
function Ground.below(position: Vector3): number?
	local origin = position + Vector3.new(0, SEARCH_UP, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -(SEARCH_UP + SEARCH_DOWN), 0), params)
	return if result then result.Position.Y else nil
end

return Ground
