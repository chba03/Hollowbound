--[[
	DEVELOPMENT ONLY. Smooth Terrain for the dev map: the island the rim town sits on,
	the crater around it (solid ground out to a ring of craggy mountains rising just
	behind the houses, so there is no gap to fall through), and the Hollow's walls,
	ledges, and floor. The sea and islands beyond are parts (DevBackdrop).

	Terrain carries the large shapes because Roblox renders, streams, and collides it far
	more cheaply than hundreds of parts, and it looks natural. Props live in DevDecor.

	It only writes inside the Hollow's own region (a column around the pit centre, plus
	the crater disc at the rim), and DevMap only calls build() when that region holds no
	terrain yet (see exists()). Terrain written during a playtest is discarded when the
	test stops; to keep it, build the map in edit mode (see README).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))

local DevTerrain = {}

local M = Enum.Material
local H = Config.Hollow

-- Terrain materials per layer, following the reference chart (Open: art direction).
--   wall: the shell; patches: embedded colour variation; outcrops: protruding rock
--   ledge: walkable shelves; pools: shallow water on ledges
local STYLE = {
	{ wall = M.Rock, patches = { M.LeafyGrass, M.Grass, M.LeafyGrass, M.Ground }, outcrops = { M.Rock, M.LeafyGrass }, ledge = M.Grass },
	{ wall = M.Ground, patches = { M.LeafyGrass, M.Mud, M.LeafyGrass }, outcrops = { M.Rock, M.Ground }, ledge = M.LeafyGrass },
	{ wall = M.Rock, patches = { M.Sandstone, M.Slate, M.Limestone }, outcrops = { M.Rock, M.Slate }, ledge = M.Slate },
	{ wall = M.Glacier, patches = { M.Ice, M.Snow, M.Slate }, outcrops = { M.Ice, M.Glacier, M.Slate }, ledge = M.Snow },
	{ wall = M.Basalt, patches = { M.Slate, M.Rock }, outcrops = { M.Basalt, M.Slate }, ledge = M.Slate, pools = true },
	{ wall = M.Ground, patches = { M.Mud, M.Rock, M.Ground }, outcrops = { M.Rock, M.Mud }, ledge = M.Ground, paths = M.Cobblestone },
	{ wall = M.Sandstone, patches = { M.Salt, M.Mud, M.Limestone }, outcrops = { M.Salt, M.Sandstone }, ledge = M.Salt },
	{ wall = M.Basalt, patches = { M.CrackedLava, M.Basalt, M.Slate }, outcrops = { M.Basalt, M.CrackedLava }, ledge = M.Basalt },
	{ wall = M.Slate, patches = { M.Mud, M.Rock, M.Ground }, outcrops = { M.Rock, M.Slate }, ledge = M.Mud },
	{ wall = M.Limestone, patches = { M.Salt, M.Glacier, M.Pavement }, outcrops = { M.Glacier, M.Limestone }, ledge = M.Pavement },
}

local SLICE = 16 -- carve the pit in slices so its radius can follow the depth profile
local SHELL = 28 -- wall thickness
local ISLAND_RADIUS = 244
local CLIFF_DEPTH = 56 -- legacy: the island's cliff boulders (now buried in the crater floor)
local CRATER_RADIUS = 600 -- solid ground from the town out to here: nothing to fall into
local CRATER_DEPTH = 112 -- the crater floor's rock reaches this far below the rim
local WALL_FOOT = 264 -- the crater wall starts rising here, just behind the houses
local WALL_TOP = 304 -- and reaches WALL_HEIGHT here
local WALL_HEIGHT = 40
local CONE_SLICE = 8

-- Height above the rim of the crater wall's base at `radius`.
local function wallHeight(radius: number): number
	local t = math.clamp((radius - WALL_FOOT) / (WALL_TOP - WALL_FOOT), 0, 1)
	return WALL_HEIGHT * t * t * (3 - 2 * t)
end
local TOWN_RADIUS = 208 -- outer edge of the cobbled road ring behind the bases
local ROAD_INNER_RADIUS = 190 -- inner edge of the road; grass inside it, under the bases
local PATCHES_PER_LAYER = 34
local OUTCROPS_PER_LAYER = 26

-- Is there terrain in the pit wall already (a saved or edit-mode build)?
function DevTerrain.exists(center: Vector3): boolean
	local probe = center + Vector3.new(H.PitRadius + SHELL / 2, -40, 0)
	local region = Region3.new(probe - Vector3.new(4, 4, 4), probe + Vector3.new(4, 4, 4)):ExpandToGrid(4)
	local materials = workspace.Terrain:ReadVoxels(region, 4)
	-- The result also carries a Size field, so walk it by index only.
	for _, plane in ipairs(materials) do
		for _, row in ipairs(plane) do
			for _, material in ipairs(row) do
				if material ~= M.Air then
					return true
				end
			end
		end
	end
	return false
end

local buildMountains: (Terrain, Vector3, () -> ()) -> ()

-- One craggy peak: stacked terrain discs narrowing to the top, each nudged sideways a
-- little. Green at the foot, rock above, a few slate bands.
local function cone(terrain: Terrain, base: Vector3, height: number, baseRadius: number, rng: Random)
	for y = 0, height, CONE_SLICE do
		local t = y / height
		local radius = math.max(baseRadius * (1 - t) ^ 1.2, 0) + 3
		local nudge = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * baseRadius * 0.07
		local material = if t < 0.22 then M.LeafyGrass elseif rng:NextNumber() < 0.2 then M.Slate else M.Rock
		terrain:FillCylinder(CFrame.new(base + Vector3.new(0, y + CONE_SLICE / 2, 0) + nudge), CONE_SLICE, radius, material)
	end
end

-- The mountain ring around the crater: a low inner row, a tall middle row, and an outer
-- row behind. Each peak's foot stays outside WALL_FOOT so nothing reaches the houses.
-- Own seed, so the Hollow's terrain is unchanged.
buildMountains = function(terrain: Terrain, center: Vector3, breathe: () -> ())
	local rng = Random.new(91)
	local rows = {
		{ count = 46, radius = 340, spread = 12, height = { 80, 150 }, footGap = 6 },
		{ count = 40, radius = 430, spread = 22, height = { 170, 300 }, footGap = 24 },
		{ count = 34, radius = 525, spread = 25, height = { 120, 230 }, footGap = 60 },
	}
	for _, row in rows do
		for i = 0, row.count - 1 do
			local angle = (i + rng:NextNumber(-0.35, 0.35)) / row.count * 2 * math.pi
			local radius = row.radius + rng:NextNumber(-row.spread, row.spread)
			local height = rng:NextNumber(row.height[1], row.height[2])
			local baseRadius = math.min(height * 0.55 + 24, radius - WALL_FOOT - row.footGap)
			local base = Vector3.new(center.X + math.cos(angle) * radius, center.Y, center.Z + math.sin(angle) * radius)
			cone(terrain, base, height, baseRadius, rng)
			breathe()
		end
	end
end

function DevTerrain.build(center: Vector3)
	local terrain = workspace.Terrain
	local rimY = center.Y
	local rng = Random.new(4242)
	local layerCount = #Config.Layers
	local totalDepth = layerCount * H.LayerHeight

	-- Large fills are slow; yield now and then so the build never trips the script timeout.
	local lastYield = os.clock()
	local function breathe()
		if os.clock() - lastYield > 0.2 then
			task.wait()
			lastYield = os.clock()
		end
	end
	local function cylinder(topY: number, height: number, radius: number, material: Enum.Material)
		if height <= 0 or radius <= 0 then
			return -- Roblox errors on empty fills, which would stop the whole build
		end
		terrain:FillCylinder(CFrame.new(center.X, topY - height / 2, center.Z), height, radius, material)
		breathe()
	end
	local function polar(radius: number, angle: number, y: number): Vector3
		return Vector3.new(center.X + math.cos(angle) * radius, y, center.Z + math.sin(angle) * radius)
	end

	-- The crater: solid rock from the pit out to CRATER_RADIUS, so there is no gap
	-- anywhere around the town, then a wall that rises from just behind the houses into a
	-- ring of craggy mountains. Everything here is within streaming range of the town.
	cylinder(rimY, CRATER_DEPTH, CRATER_RADIUS, M.Rock)
	cylinder(rimY + WALL_HEIGHT, WALL_HEIGHT, CRATER_RADIUS, M.Rock)
	for radius = WALL_TOP - 4, WALL_FOOT - 4, -4 do
		cylinder(rimY + WALL_HEIGHT, WALL_HEIGHT - wallHeight(radius), radius, M.Air)
	end
	-- Scenery only: if the mountains fail, warn and still build the town and the Hollow.
	local ok, err = pcall(function()
		buildMountains(terrain, center, breathe)
		-- Green lower slopes: grass on the wall's base and the mountains' feet.
		local slopes = Region3.new(
			center + Vector3.new(-CRATER_RADIUS, 1, -CRATER_RADIUS),
			center + Vector3.new(CRATER_RADIUS, WALL_HEIGHT * 0.7, CRATER_RADIUS)
		):ExpandToGrid(4)
		terrain:ReplaceMaterial(slopes, 4, M.Rock, M.LeafyGrass)
	end)
	if not ok then
		warn("[Hollowbound] Crater mountains failed: " .. tostring(err))
	end
	breathe()

	-- Craggy island cliffs.
	for _ = 1, 30 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local size = rng:NextNumber(10, 20)
		local y = rimY - rng:NextNumber(8, CLIFF_DEPTH + 10)
		terrain:FillBall(polar(ISLAND_RADIUS + size * 0.3, angle, y), size, if rng:NextNumber() < 0.7 then M.Rock else M.Slate)
	end

	-- Pit wall shell, then the hollow itself, slice by slice.
	for depth = 0, totalDepth - SLICE, SLICE do
		local mid = depth + SLICE / 2
		local layer = Progression.layerForDepth(mid)
		cylinder(rimY - depth, SLICE, Progression.pitRadiusAt(mid) + SHELL, STYLE[layer].wall)
	end

	-- Town surface: grassy cliff tops for the bases, a cobbled road ring behind them,
	-- and grass again out to the island's edge.
	cylinder(rimY, 4, WALL_FOOT + 8, M.Grass) -- grass right up to the crater wall
	cylinder(rimY, 4, TOWN_RADIUS, M.Cobblestone)
	cylinder(rimY, 4, ROAD_INNER_RADIUS, M.Grass)
	-- Under each base: leafy grass, which has no tall blades, so pedestals, relics, and
	-- the upgrade panels stay clear. The open grass elsewhere keeps its blades.
	for i = 0, Config.Plots.Count - 1 do
		local angle = i / Config.Plots.Count * 2 * math.pi
		local plotCenter = polar(Config.Plots.Radius, angle, rimY - 2)
		local facing = CFrame.lookAt(plotCenter, Vector3.new(center.X, rimY - 2, center.Z))
		terrain:FillBlock(facing, Vector3.new(Config.Plots.Size + 8, 4, Config.Plots.Size + 8), M.LeafyGrass)
	end
	-- Shorter grass blades where Roblox allows it (not every version has this setting).
	local shortened = pcall(function()
		(terrain :: any).GrassLength = 0.55
	end)
	if not shortened then
		print("[Hollowbound] Terrain grass length can't be set from a script here; set Terrain > GrassLength in Studio if it exists.")
	end

	-- Rocky outcrops in the gaps between bases and along the lip there (own seed, so the
	-- Hollow's terrain below is unchanged). They stay outside the pit and off the plots.
	local rocks = Random.new(77)
	local step = 2 * math.pi / Config.Plots.Count
	for i = 0, Config.Plots.Count - 1 do
		for _ = 1, 9 do
			local angle = i * step + step / 2 + rocks:NextNumber(-step * 0.18, step * 0.18)
			local size = rocks:NextNumber(4, 9)
			local radius = rocks:NextNumber(H.PitRadius + 6 + size / 2, ROAD_INNER_RADIUS - 4)
			terrain:FillBall(polar(radius, angle, rimY - size * 0.25), size / 2, if rocks:NextNumber() < 0.6 then M.Rock else M.Slate)
		end
		for _ = 1, 3 do
			local angle = i * step + step / 2 + rocks:NextNumber(-step * 0.2, step * 0.2)
			terrain:FillBall(polar(rocks:NextNumber(150, 185), angle, rimY), rocks:NextNumber(2, 3), M.LeafyGrass)
		end
	end
	for _ = 1, 24 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		terrain:FillBall(polar(rng:NextNumber(TOWN_RADIUS + 6, ISLAND_RADIUS - 6), angle, rimY - 1), rng:NextNumber(5, 9), M.LeafyGrass)
	end

	for depth = 0, totalDepth - SLICE, SLICE do
		local mid = depth + SLICE / 2
		cylinder(rimY - depth, SLICE, Progression.pitRadiusAt(mid), M.Air)
	end
	cylinder(rimY + 12, 12, H.PitRadius, M.Air) -- nothing hangs over the lip

	for layer, style in STYLE do
		local topDepth = (layer - 1) * H.LayerHeight

		-- Embedded colour patches: mostly inside the wall, showing as surface variation.
		for _ = 1, PATCHES_PER_LAYER do
			local depth = topDepth + rng:NextNumber(4, H.LayerHeight - 4)
			local size = rng:NextNumber(8, 16)
			local angle = rng:NextNumber(0, 2 * math.pi)
			local material = style.patches[rng:NextInteger(1, #style.patches)]
			terrain:FillBall(polar(Progression.pitRadiusAt(depth) + size * 0.8, angle, rimY - depth), size, material)
		end

		-- Outcrops: protrude at most ~0.45 x size, so ropes (radius 100) stay clear.
		for _ = 1, OUTCROPS_PER_LAYER do
			local depth = topDepth + rng:NextNumber(4, H.LayerHeight - 4)
			local size = rng:NextNumber(6, 13)
			local angle = rng:NextNumber(0, 2 * math.pi)
			local material = style.outcrops[rng:NextInteger(1, #style.outcrops)]
			terrain:FillBall(polar(Progression.pitRadiusAt(depth) + size * 0.55, angle, rimY - depth), size, material)
		end
		breathe()

		-- Ledges: a ring from LedgeInnerRadius out into the wall.
		for _, ledgeDepth in H.LedgeDepths do
			local depth = topDepth + ledgeDepth
			local top = rimY - depth
			local wallRadius = Progression.pitRadiusAt(depth)
			cylinder(top, 8, wallRadius + 6, style.ledge)
			if style.pools then
				cylinder(top + 2, 2, wallRadius + 2, M.Water)
			end
			if style.paths then
				for _ = 1, 6 do
					local angle = rng:NextNumber(0, 2 * math.pi)
					local r = rng:NextNumber(H.LedgeInnerRadius + 6, wallRadius - 4)
					terrain:FillBlock(
						CFrame.new(polar(r, angle, top - 1)) * CFrame.Angles(0, -angle, 0),
						Vector3.new(6, 2, rng:NextNumber(8, 16)),
						style.paths
					)
				end
			end
			-- Carve the inner edge (pools keep a dry lip so the edge reads clearly).
			cylinder(top + 4, 12, H.LedgeInnerRadius, M.Air)
			if style.pools then
				cylinder(top + 4, 4, H.LedgeInnerRadius + 3, M.Air)
			end
		end
	end

	-- Floor of the last layer.
	cylinder(rimY - totalDepth, 8, Progression.pitRadiusAt(totalDepth) + SHELL, STYLE[layerCount].wall)
	cylinder(rimY - totalDepth, 4, Progression.pitRadiusAt(totalDepth) + 2, STYLE[layerCount].ledge)
end

return DevTerrain
