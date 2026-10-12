--[[
	DEVELOPMENT ONLY. The world beyond the crater's mountains (DevTerrain): open sea out
	to the horizon and a few distant islands.

	Built from large parts in one Persistent model, not terrain: terrain only streams in
	within about 1,000 studs of a player, so a far sea of terrain would vanish and leave
	the empty void. Persistent parts are always there.

	Low-poly peaks: a cube stood on its corner and half sunk reads as a faceted mountain
	top (used for the islands). Every part is anchored, non-colliding, non-queryable, and
	shadowless. About 70 parts.
]]

local DevBackdrop = {}

local M = Enum.Material
local TAU = 2 * math.pi

local ROCK = { Color3.fromRGB(176, 164, 142), Color3.fromRGB(158, 148, 132), Color3.fromRGB(190, 178, 156) }
local FOREST = { Color3.fromRGB(62, 112, 58), Color3.fromRGB(74, 126, 64), Color3.fromRGB(56, 100, 54) }
local SEA = Color3.fromRGB(56, 112, 156)

local SEA_DEPTH = 80 -- sea surface, studs below the rim
local SEA_EXTENT = 4096 -- the sea reaches this far from the pit in every direction
local MAX_TILE = 2048 -- largest part size Roblox allows
local HOLE_RADIUS = 590 -- no sea inside this (just inside the crater's rock, radius 600)
local PIT_CLEARANCE = 220 -- never place a tile within this of the pit centre

-- Tips a cube onto one corner (the long diagonal points up).
local CORNER_UP = CFrame.Angles(math.rad(45), 0, math.atan(1 / math.sqrt(2)))

local function piece(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A faceted peak whose tip stands `height` above `base` (a point at sea level), `width`
-- across at its widest. Stretching the cube makes ridges rather than perfect pyramids.
local function peak(parent: Instance, name: string, base: Vector3, width: number, height: number, yaw: number, color: Color3, material: Enum.Material, rng: Random)
	local edge = width * 0.8
	local stretch = Vector3.new(edge * rng:NextNumber(0.8, 1.25), edge, edge * rng:NextNumber(0.8, 1.25))
	-- The top corner sits about 0.85 x edge above the cube's centre.
	local centreY = base.Y + height - edge * 0.85
	local cframe = CFrame.new(base.X, centreY, base.Z) * CFrame.Angles(0, yaw, 0) * CORNER_UP
	piece(parent, name, stretch, cframe, color, material)
end

-- Builds the backdrop around `center` (the pit centre at rim height).
function DevBackdrop.build(map: Instance, center: Vector3)
	local rng = Random.new(5150)
	local model = Instance.new("Model")
	model.Name = "Backdrop"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = map

	local seaY = center.Y - SEA_DEPTH
	local function around(radius: number, angle: number): Vector3
		return Vector3.new(center.X + math.cos(angle) * radius, seaY, center.Z + math.sin(angle) * radius)
	end

	-- Sea: a plane of large tiles out to the horizon. Inside the crater it lies under the
	-- crater's rock, so only the sea beyond the mountains shows.
	-- Covers the square (x0, z0, size) with tiles, leaving out everything inside the
	-- crater: squares wholly within HOLE_RADIUS are skipped (the crater's rock hides that
	-- area anyway), and squares touching the pit are split until they can be skipped.
	-- Without the hole, the sea plane shows through the pit as a blue disc.
	local function cover(x0: number, z0: number, size: number)
		local corners = 0
		for _, corner in { { x0, z0 }, { x0 + size, z0 }, { x0, z0 + size }, { x0 + size, z0 + size } } do
			if Vector2.new(corner[1], corner[2]).Magnitude <= HOLE_RADIUS then
				corners += 1
			end
		end
		if corners == 4 then
			return -- entirely under the crater
		end
		local nearestX = math.clamp(0, x0, x0 + size)
		local nearestZ = math.clamp(0, z0, z0 + size)
		local touchesPit = Vector2.new(nearestX, nearestZ).Magnitude < PIT_CLEARANCE
		if touchesPit or size > MAX_TILE then
			local half = size / 2
			cover(x0, z0, half)
			cover(x0 + half, z0, half)
			cover(x0, z0 + half, half)
			cover(x0 + half, z0 + half, half)
			return
		end
		local tile = piece(model, "Sea", Vector3.new(size, 2, size), CFrame.new(center.X + x0 + size / 2, seaY - 1, center.Z + z0 + size / 2), SEA, M.SmoothPlastic)
		tile.Reflectance = 0.08
	end
	cover(-SEA_EXTENT, -SEA_EXTENT, SEA_EXTENT * 2)

	-- Distant islands on the horizon.
	for _ = 1, 14 do
		local position = around(rng:NextNumber(1700, 3200), rng:NextNumber(0, TAU))
		local width = rng:NextNumber(180, 420)
		peak(model, "Island", position, width, rng:NextNumber(30, 110), rng:NextNumber(0, TAU), FOREST[rng:NextInteger(1, #FOREST)], M.Grass, rng)
		peak(model, "IslandRock", position + Vector3.new(rng:NextNumber(-40, 40), 0, rng:NextNumber(-40, 40)), width * 0.5, rng:NextNumber(50, 150), rng:NextNumber(0, TAU), ROCK[1], M.Rock, rng)
	end
end

return DevBackdrop
