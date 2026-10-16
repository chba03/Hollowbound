--[[
	Authored layout of the vertical world (milestone 5). Deterministic data only: the same
	file always produces the same world. Positions are relative to Config.World.Origin
	(the rim center at the walkable rim surface).

	Conventions (see Geometry): angles in degrees (0 = +X, 90 = +Z); depth d is studs
	below the rim surface (y = -d); "inset" is distance in from the shaft wall.

	Names below (places, buildings, creatures) are original and provisional.

	Map overview (top view, angles):
	          90  Guardian clearing below; overlook at 110
	   180  ---+---  0   Service district (spawn, registry, workshop, depot) at 0;
	   Elder Tree at 165, camp at 182-208 (depth 230)     Descent Gate at 20
	          270  overlook at 290; floor landing at 290
]]

local Layout = {}

-- Shaft wall: radius at each depth (before wobble). Rings of rock are built every
-- RingHeight studs down to the floor; each ring uses the widest radius it spans, so a
-- wall never juts into a route.
Layout.ShaftProfile = {
	{ depth = 0, radius = 210 },
	{ depth = 40, radius = 206 },
	{ depth = 90, radius = 198 },
	{ depth = 140, radius = 224 },
	{ depth = 200, radius = 250 },
	{ depth = 260, radius = 244 },
	{ depth = 320, radius = 230 },
	{ depth = 380, radius = 238 },
}
Layout.RingHeight = 40
Layout.WallSegments = 24
Layout.WallThickness = 64
-- Deterministic irregularity by angle only (so every ring and route agrees).
Layout.Wobble = {
	{ amplitude = 8, lobes = 5, phase = 0.7 },
	{ amplitude = 4, lobes = 11, phase = 2.1 },
}

-- Rim town.
Layout.Town = {
	RingSegments = 36,
	ParapetHeight = 3.5,
	ParapetGaps = { { from = 14, to = 26 }, { from = 104, to = 116 }, { from = 194, to = 206 }, { from = 284, to = 296 } },
	Overlooks = {
		{ name = "Sunward Overlook", angle = 110 },
		{ name = "Mistfall Overlook", angle = 200 },
		{ name = "Eastward Overlook", angle = 290 },
	},
	LanternAngles = { 0, 35, 60, 90, 130, 150, 180, 220, 240, 270, 310, 340 },
	SpawnPlaza = { angle = 0, radius = 262 },
	-- Service district (the detailed one) around angle 0.
	Services = {
		Registry = { angle = -12, radius = 322, width = 30, depth = 22, name = "Registry Hall" },
		Workshop = { angle = 12, radius = 322, width = 26, depth = 20, name = "Relic Workshop" },
		Depot = { angle = 27, radius = 316, width = 20, depth = 16, name = "Supply Depot" },
		Crane = { angle = 6, radius = 216 }, -- relic-powered lift crane at the edge (decor)
		Gate = { angle = 20, radius = 212, name = "Descent Gate" },
	},
	-- Other buildings around the circumference (kind, angle, radius, width, depth, floors).
	Buildings = {
		{ kind = "Lodge", angle = 48, radius = 318, width = 24, depth = 18, floors = 2, name = "Cliffside Lodge" },
		{ kind = "Lodge", angle = 72, radius = 322, width = 22, depth = 18, floors = 2, name = "Lanternkeepers' Lodge" },
		{ kind = "Workshop", angle = 95, radius = 320, width = 24, depth = 18, floors = 1, name = "Ropewright" },
		{ kind = "Lodge", angle = 132, radius = 318, width = 26, depth = 20, floors = 2, name = "Gardeners' Lodge" },
		{ kind = "Lodge", angle = 156, radius = 322, width = 22, depth = 18, floors = 2, name = "Wayfarers' Lodge" },
		{ kind = "Tower", angle = 180, radius = 320, width = 16, depth = 16, floors = 4, name = "Bellwatch Tower" },
		{ kind = "Lodge", angle = 222, radius = 318, width = 24, depth = 18, floors = 2, name = "Deepcallers' Lodge" },
		{ kind = "Workshop", angle = 246, radius = 322, width = 22, depth = 18, floors = 1, name = "Lensgrinder" },
		{ kind = "Lodge", angle = 270, radius = 318, width = 24, depth = 20, floors = 2, name = "Rimwalkers' Lodge" },
		{ kind = "Tower", angle = 304, radius = 320, width = 14, depth = 14, floors = 3, name = "Signal Tower" },
		{ kind = "Lodge", angle = 326, radius = 320, width = 22, depth = 18, floors = 2, name = "Old Guild Lodge" },
	},
	OuterRidges = 24,
}

-- Main route (both directions). Wall nodes hug the shaft wall at `inset`; the planner
-- builds ramps between consecutive nodes and a landing at each node.
Layout.Route = {
	Width = 12,
	Inset = 12,
	MaxSlopeDegrees = 35,
	-- Gate to the root bridge (upper shaft).
	Upper = {
		{ id = "Gate", angle = 20, depth = 0 },
		{ id = "U1", angle = 32, depth = 20 },
		{ id = "U2", angle = 44, depth = 40 },
		{ id = "ShelfWest", angle = 56, depth = 60 },
		{ id = "ShelfEast", angle = 84, depth = 60 },
		{ id = "U3", angle = 96, depth = 80 },
		{ id = "U4", angle = 108, depth = 100 },
		{ id = "U5", angle = 120, depth = 120 },
		{ id = "BridgeHead", angle = 132, depth = 140 },
	},
	-- Camp to the floor along the east wall, with a scaffold ladder.
	East = {
		{ id = "CampExit", angle = 208, depth = 230 },
		{ id = "E1", angle = 220, depth = 250 },
		{ id = "E2", angle = 232, depth = 270 },
		{ id = "E3", angle = 244, depth = 290 },
		{ id = "E4", angle = 256, depth = 310 },
		{ id = "ScaffoldTop", angle = 266, depth = 310 },
		{ id = "ScaffoldBottom", angle = 266, depth = 355, ladder = true },
		{ id = "E5", angle = 278, depth = 368 },
		{ id = "FloorLanding", angle = 290, depth = 380 },
	},
	-- Optional branch: a flat ledge from the bridge head to the Lantern Ruins.
	Branch = {
		{ id = "BridgeHead", angle = 132, depth = 140 },
		{ id = "RuinsLedge", angle = 146, depth = 140 },
	},
}

-- The Elder Tree: a giant tree rooted on the floor, with a spiral walkway around its
-- trunk from the root bridge down to the floor (the alternate route).
Layout.ElderTree = {
	angle = 165,
	radius = 145,
	trunkRadius = 12,
	topDepth = 105, -- trunk top; the canopy spreads around it
	spiralTopDepth = 140,
	spiralRadius = 17, -- walkway center distance from the trunk axis
	spiralWidth = 10,
	stepDegrees = 36,
	stepDrop = 6,
	campDepth = 230, -- the walkway node nearest this depth, facing the camp, links to camp
}

-- Shelves: flat platforms against the wall (angle range at one depth, extending in).
Layout.Shelves = {
	{ name = "Overhang Shelf", from = 54, to = 86, depth = 60, inset = 40 },
	{ name = "Lantern Ruins", from = 140, to = 158, depth = 140, inset = 30 },
	{ name = "Mistfall Camp", from = 182, to = 208, depth = 230, inset = 48, camp = true },
}

-- Floor features.
Layout.Floor = {
	TileSize = 40,
	Pit = { angle = 200, radius = 60, size = 34 }, -- the closed way further down
	Trees = {
		{ angle = 300, radius = 120, height = 70, canopy = 22 },
		{ angle = 340, radius = 200, height = 60, canopy = 18 },
		{ angle = 45, radius = 110, height = 80, canopy = 24 },
		{ angle = 120, radius = 190, height = 55, canopy = 16 },
		{ angle = 235, radius = 150, height = 65, canopy = 20 },
		{ angle = 15, radius = 210, height = 50, canopy = 15 },
	},
	Ruins = {
		{ kind = "Arch", angle = 0, radius = 90, yaw = 30 },
		{ kind = "Pillar", angle = 20, radius = 70 },
		{ kind = "Pillar", angle = 335, radius = 100 },
		{ kind = "Wall", angle = 60, radius = 130, yaw = 75 },
		{ kind = "Arch", angle = 270, radius = 170, yaw = 5 },
		{ kind = "FallenPillar", angle = 250, radius = 110, yaw = 40 },
		{ kind = "Pillar", angle = 140, radius = 120 },
	},
	-- Creature territory (regular dens) and the guardian clearing with its cache.
	Dens = {
		{ name = "ThornbackDenNorth", angle = 330, radius = 150 },
		{ name = "ThornbackDenEast", angle = 30, radius = 165 },
	},
	Guardian = { angle = 85, radius = 160, cacheRadius = 196, encounterId = "VerdantRootwarden", stones = 8, stoneRing = 30 },
	-- Windhook-only discovery: a ledge too high to jump onto from the floor.
	SkyLedge = { angle = 118, height = 10, size = 14 },
}

-- Waterfalls (non-colliding, non-queryable sheets) with mist at the bottom.
Layout.Waterfalls = {
	{ angle = 255, topDepth = 90, bottomDepth = 380, width = 14, pool = true },
	{ angle = 152, topDepth = 8, bottomDepth = 140, width = 6, pool = false },
}

-- Relic spawn pedestals A-E (Config.TestSpecimens uses these names).
Layout.RelicSpawns = {
	{ name = "RelicSpawnA", place = "LanternRuins", offset = -4 },
	{ name = "RelicSpawnB", place = "LanternRuins", offset = 4 },
	{ name = "RelicSpawnC", place = "Floor", angle = 248, radius = 196 }, -- by the waterfall pool
	{ name = "RelicSpawnD", place = "Floor", angle = 10, radius = 120 }, -- inside Thornback range
	{ name = "RelicSpawnE", place = "SkyLedge" }, -- Windhook only
}

-- Named places for the HUD (cylinders: center, radius, height band). Higher priority
-- wins where they overlap. Town and camp zones name themselves.
Layout.Regions = {
	{ name = "The Descent Gate", angle = 20, radius = 205, depth = 0, size = 26, height = 16, priority = 2 },
	{ name = "Overhang Shelf", angle = 70, radius = 190, depth = 60, size = 60, height = 30, priority = 2 },
	{ name = "Lantern Ruins", angle = 149, radius = 210, depth = 140, size = 40, height = 30, priority = 3 },
	{ name = "Root Bridge", angle = 145, radius = 175, depth = 140, size = 55, height = 20, priority = 2 },
	{ name = "The Elder Tree", angle = 165, radius = 145, depth = 260, size = 40, height = 260, priority = 1 },
	{ name = "Thornback Range", angle = 0, radius = 150, depth = 380, size = 95, height = 50, priority = 2 },
	{ name = "Rootwarden Clearing", angle = 85, radius = 172, depth = 380, size = 50, height = 50, priority = 3 },
	{ name = "Mistfall Pool", angle = 252, radius = 200, depth = 380, size = 35, height = 40, priority = 2 },
}

Layout.Vines = {
	UnderRimEvery = 10, -- degrees between vines hanging below the rim edge
	PerShelf = 8,
}

return Layout
