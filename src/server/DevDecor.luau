--[[
	DEVELOPMENT ONLY. Props for the dev map: lamps and vines on the pit lip, and each
	Hollow layer's signature features from the reference chart:
	  1 Mistfall Gardens   trees, hanging gardens, vines, flowers, small falls from the rim
	  2 The Hanging Wood   upside-down trees and moss under the ledges
	  3 Veilfall Cliffs    great waterfalls down sheer cliff columns
	  4 Glasswood Hollows  tall cup-shaped trees and ice crystals
	  5 Drowned Terraces   water spilling from ledge to ledge, stepped stone
	  6 Rootbound Ruins    giant roots, broken buildings, old machinery
	  7 The Marrow         fibrous strands, glowing pods
	  8 Emberdeep Forges   lava falls, glowing magma veins, brass pipes, old furnaces
	  9 Gloamcap Grotto    giant glowing mushrooms, shelf fungi, hanging glow tendrils
	 10 The Lumen Core     pale crystal spires, floating stones, light at the very bottom

	Performance rules for everything here:
	  - Props are anchored, non-colliding, non-queryable, and cast no shadows, so they
	    cost almost nothing in physics and keep ropes, ledges, and pickups unobstructed.
	  - Counts are fixed and small (roughly 1000 parts for the whole Hollow). Terrain
	    (DevTerrain) carries the large shapes.
	  - Few lights (about 65) and few particle emitters (about 30, low rates).
	  - Placement is seeded, so every build is identical.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))
local DevBase = require(script.Parent.DevBase)

local DevDecor = {}

local M = Enum.Material
local H = Config.Hollow
local TAU = 2 * math.pi
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local center: Vector3
local rimY: number
local rng: Random

-- Primitives ------------------------------------------------------------------------

local function prop(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
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
	p.Material = material or M.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ball(parent: Instance, name: string, diameter: number, position: Vector3, color: Color3, material: Enum.Material?): Part
	return prop(parent, name, Vector3.one * diameter, CFrame.new(position), color, material, Enum.PartType.Ball)
end

-- Vertical cylinder centred on `position`.
local function column(parent: Instance, name: string, height: number, diameter: number, position: Vector3, color: Color3, material: Enum.Material?): Part
	return prop(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

-- Cylinder running from a to b.
local function strand(parent: Instance, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?): Part
	return prop(
		parent,
		name,
		Vector3.new((b - a).Magnitude, diameter, diameter),
		CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

-- Block whose long (Y) axis points from base toward target.
local function spike(parent: Instance, name: string, base: Vector3, target: Vector3, width: number, length: number, color: Color3, material: Enum.Material?): Part
	local direction = (target - base).Unit
	local cframe = CFrame.lookAt(base + direction * length / 2, base + direction * length) * CFrame.Angles(-math.pi / 2, 0, 0)
	return prop(parent, name, Vector3.new(width, length, width), cframe, color, material)
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = parent
end

local function shade(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + rng:NextNumber(-amount, amount), 0, 1))
end

-- Geometry --------------------------------------------------------------------------

local function polar(radius: number, angle: number, y: number): Vector3
	return Vector3.new(center.X + math.cos(angle) * radius, y, center.Z + math.sin(angle) * radius)
end

local function inward(angle: number): Vector3
	return -Vector3.new(math.cos(angle), 0, math.sin(angle))
end

local function layerTop(layer: number): number
	return (layer - 1) * H.LayerHeight
end

-- Point on the pit wall: inset > 0 moves inward from the wall face.
local function wallPoint(depth: number, angle: number, inset: number): Vector3
	return polar(Progression.pitRadiusAt(depth) - inset, angle, rimY - depth)
end

-- Point on top of a ledge: t = 0 at the inner edge, 1 at the wall.
local function ledgePoint(layer: number, ledge: number, angle: number, t: number): Vector3
	local depth = layerTop(layer) + H.LedgeDepths[ledge]
	local r = H.LedgeInnerRadius + (Progression.pitRadiusAt(depth) - H.LedgeInnerRadius) * t
	return polar(r, angle, rimY - depth)
end

local function ledgeDepth(layer: number, ledge: number): number
	return layerTop(layer) + H.LedgeDepths[ledge]
end

-- Angles away from the plots' rope lines, for anything near the inner ledge edge.
local function betweenRopes(): number
	local step = TAU / Config.Plots.Count
	return (rng:NextInteger(0, Config.Plots.Count - 1) + 0.5) * step + rng:NextNumber(-0.12, 0.12)
end

-- Shared features -------------------------------------------------------------------

local function mist(parent: Instance, position: Vector3, size: number, rate: number, color: Color3?)
	local holder = prop(parent, "Mist", Vector3.one, CFrame.new(position), Color3.new(1, 1, 1))
	holder.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE
	emitter.Color = ColorSequence.new(color or Color3.fromRGB(245, 250, 255))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.4), NumberSequenceKeypoint.new(1, size) })
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(3, 5)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-10, 10)
	emitter.LightEmission = 0.15
	emitter.Parent = holder
end

-- A falling sheet of water: a foam lip holding a camera-facing, scrolling beam.
local function waterfall(parent: Instance, top: Vector3, length: number, width: number, splash: boolean?)
	-- Face the pit centre so the lip runs along the wall.
	local toCenter = Vector3.new(center.X - top.X, 0, center.Z - top.Z)
	local facing = if toCenter.Magnitude > 0.1 then CFrame.lookAt(top, top + toCenter) else CFrame.new(top)
	local lip = prop(parent, "Waterfall", Vector3.new(width, 1, 1.5), facing, Color3.fromRGB(235, 245, 250), M.SmoothPlastic)
	lip.Transparency = 0.3

	local a0 = Instance.new("Attachment")
	a0.Parent = lip
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -length, 0)
	a1.Parent = lip

	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.Width0 = width
	beam.Width1 = width * 1.2
	beam.Texture = SMOKE
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 14
	beam.TextureSpeed = 1.4
	beam.Color = ColorSequence.new(Color3.fromRGB(240, 250, 255), Color3.fromRGB(200, 230, 245))
	beam.Transparency = NumberSequence.new(0.1, 0.35)
	beam.LightEmission = 0.25
	beam.LightInfluence = 0.7
	beam.Segments = 1
	beam.Parent = lip

	-- A second, slower layer gives the sheet depth.
	local under = beam:Clone()
	under.Width0 = width * 0.8
	under.Width1 = width
	under.TextureLength = 30
	under.TextureSpeed = 0.7
	under.Transparency = NumberSequence.new(0.35, 0.55)
	under.Parent = lip

	if splash ~= false then
		mist(parent, top - Vector3.new(0, length - 2, 0), width * 1.4, math.clamp(width / 3, 2, 8))
	end
end

local function tree(parent: Instance, base: Vector3, height: number, canopy: number, trunkColor: Color3, leafColor: Color3)
	column(parent, "Trunk", height, math.max(1.2, height / 9), base + Vector3.new(0, height / 2, 0), trunkColor, M.Wood)
	ball(parent, "Canopy", canopy, base + Vector3.new(0, height, 0), shade(leafColor, 0.08), M.Grass)
	ball(parent, "Canopy", canopy * 0.7, base + Vector3.new(canopy * 0.3, height - canopy * 0.25, canopy * 0.2), shade(leafColor, 0.1), M.Grass)
end

local function lantern(parent: Instance, position: Vector3, color: Color3)
	local p = prop(parent, "Lantern", Vector3.new(1, 1.6, 1), CFrame.new(position), color, M.Neon)
	light(p, color, 34, 1.4)
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Town ------------------------------------------------------------------------------

local function buildTown(map: Instance)
	-- Houses, windmills, and scenery around the bases live in DevBase.buildTown. The
	-- houses that used to be built here drew from the shared seeded generator; keep the
	-- same draws so every Hollow layer's props stay exactly where they were.
	for _ = 1, Config.Plots.Count * 4 do
		rng:NextNumber(7, 11)
		rng:NextInteger(1, 4)
		rng:NextInteger(1, 3)
	end
	local town = folder(map, "PitLip")

	-- Lamps around the lip of the pit.
	for i = 0, 15 do
		local angle = (i + 0.5) / 16 * TAU
		local base = polar(H.PitRadius + 3, angle, rimY)
		column(town, "LampPost", 8, 0.5, base + Vector3.new(0, 4, 0), Color3.fromRGB(60, 55, 50), M.Metal)
		local bulb = ball(town, "Lamp", 1.4, base + Vector3.new(0, 8.4, 0), Color3.fromRGB(255, 214, 150), M.Neon)
		if i % 2 == 0 then
			light(bulb, Color3.fromRGB(255, 200, 130), 22, 1)
		end
	end

	-- Greenery spilling over the lip, like the chart's flowering vines.
	for _ = 1, 26 do
		local angle = rng:NextNumber(0, TAU)
		local lip = polar(H.PitRadius - 0.5, angle, rimY - 1)
		ball(town, "LipBush", rng:NextNumber(3, 5), lip, shade(Color3.fromRGB(70, 130, 60), 0.1), M.Grass)
		local length = rng:NextNumber(10, 34)
		prop(town, "Vine", Vector3.new(0.35, length, 0.35), CFrame.new(lip - Vector3.new(0, length / 2, 0)), shade(Color3.fromRGB(60, 120, 55), 0.1), M.Grass)
		if rng:NextNumber() < 0.5 then
			ball(town, "Flower", 0.9, lip + Vector3.new(0, 1.6, 0), Color3.fromRGB(250, 250, 245))
		end
	end
end

-- Layers ----------------------------------------------------------------------------

local function gardens(f: Folder)
	local layer = 1
	for ledge = 1, #H.LedgeDepths do
		for _ = 1, 8 do
			local base = ledgePoint(layer, ledge, rng:NextNumber(0, TAU), rng:NextNumber(0.7, 0.95))
			tree(f, base, rng:NextNumber(8, 14), rng:NextNumber(7, 10), Color3.fromRGB(95, 70, 45), Color3.fromRGB(80, 150, 65))
			ball(f, "Flower", 0.8, base + Vector3.new(rng:NextNumber(-3, 3), 0.4, rng:NextNumber(-3, 3)), Color3.fromRGB(250, 250, 240))
		end
	end
	-- Hanging gardens on the cliff face, trailing vines.
	for _ = 1, 18 do
		local depth = rng:NextNumber(8, H.LayerHeight - 8)
		local angle = rng:NextNumber(0, TAU)
		local size = rng:NextNumber(5, 9)
		local clump = wallPoint(depth, angle, size * 0.2)
		ball(f, "HangingGarden", size, clump, shade(Color3.fromRGB(85, 155, 70), 0.1), M.Grass)
		for _ = 1, 2 do
			local length = rng:NextNumber(8, 24)
			local top = clump + Vector3.new(rng:NextNumber(-2, 2), -size * 0.3, rng:NextNumber(-2, 2))
			prop(f, "Vine", Vector3.new(0.3, length, 0.3), CFrame.new(top - Vector3.new(0, length / 2, 0)), shade(Color3.fromRGB(70, 135, 60), 0.1), M.Grass)
		end
	end
	-- Two slender falls from the rim to the first ledge.
	for _, angle in { math.rad(70), math.rad(250) } do
		waterfall(f, wallPoint(0, angle, 1.5) - Vector3.new(0, 1, 0), H.LedgeDepths[1] - 1, 7)
	end
end

local function hangingWood(f: Folder)
	local layer = 2
	local bark, leaves = Color3.fromRGB(85, 75, 60), Color3.fromRGB(95, 125, 85)
	for ledge = 1, #H.LedgeDepths do
		local underside = rimY - ledgeDepth(layer, ledge) - 8
		for _ = 1, 7 do
			-- Upside-down trees hanging from the ledge's underside.
			local angle = rng:NextNumber(0, TAU)
			local point = ledgePoint(layer, ledge, angle, rng:NextNumber(0.6, 0.9))
			local base = Vector3.new(point.X, underside, point.Z)
			local height = rng:NextNumber(8, 14)
			column(f, "Trunk", height, 1.4, base - Vector3.new(0, height / 2, 0), bark, M.Wood)
			ball(f, "Canopy", rng:NextNumber(7, 9), base - Vector3.new(0, height, 0), shade(leaves, 0.08), M.Grass)
		end
		for _ = 1, 10 do
			local point = ledgePoint(layer, ledge, rng:NextNumber(0, TAU), rng:NextNumber(0.3, 0.95))
			local length = rng:NextNumber(5, 16)
			prop(f, "Moss", Vector3.new(0.4, length, 0.4), CFrame.new(Vector3.new(point.X, underside - length / 2, point.Z)), shade(Color3.fromRGB(130, 150, 115), 0.1), M.Grass)
		end
		for _ = 1, 3 do
			local base = ledgePoint(layer, ledge, rng:NextNumber(0, TAU), rng:NextNumber(0.75, 0.95))
			tree(f, base, rng:NextNumber(10, 15), rng:NextNumber(7, 9), bark, leaves)
		end
	end
	-- Great trees growing sideways out of the wall, crowns hanging down.
	for _ = 1, 8 do
		local depth = rng:NextNumber(20, H.LayerHeight - 30) + layerTop(layer)
		local angle = rng:NextNumber(0, TAU)
		local root = wallPoint(depth, angle, -2)
		local tip = wallPoint(depth + 12, angle, 10)
		strand(f, "Trunk", root, tip, 2.4, bark, M.Wood)
		ball(f, "Canopy", rng:NextNumber(9, 11), tip - Vector3.new(0, 4, 0), shade(leaves, 0.08), M.Grass)
	end
end

local function veilfall(f: Folder)
	local layer = 3
	local top = layerTop(layer)
	-- Sheer cliff columns emphasise the vertical wall.
	for _ = 1, 12 do
		local angle = rng:NextNumber(0, TAU)
		local height = rng:NextNumber(60, 140)
		local depth = top + rng:NextNumber(height / 2, H.LayerHeight - height / 2)
		column(f, "CliffColumn", height, rng:NextNumber(6, 10), wallPoint(depth, angle, -2), shade(Color3.fromRGB(120, 100, 80), 0.08), M.Rock)
	end
	-- The great falls, pouring the full height of the layer.
	for i = 0, 5 do
		local angle = (i / 6) * TAU + math.rad(15)
		waterfall(f, wallPoint(top, angle, 2), H.LayerHeight, rng:NextNumber(18, 26))
	end
	-- Smaller falls between the ledges.
	for _ = 1, 4 do
		local angle = rng:NextNumber(0, TAU)
		local from = ledgeDepth(layer, 1)
		waterfall(f, wallPoint(from, angle, 2), H.LedgeDepths[2] - H.LedgeDepths[1], 7, false)
	end
end

local function glasswood(f: Folder)
	local layer = 4
	local trunk, cup, rim = Color3.fromRGB(120, 160, 160), Color3.fromRGB(85, 195, 185), Color3.fromRGB(150, 230, 215)
	local function cupTree(base: Vector3, height: number, width: number)
		column(f, "Stem", height, math.max(1.4, width / 10), base + Vector3.new(0, height / 2, 0), trunk, M.SmoothPlastic)
		column(f, "CupBase", 1.2, width * 0.45, base + Vector3.new(0, height - 1, 0), trunk, M.SmoothPlastic)
		column(f, "Cup", 1.6, width, base + Vector3.new(0, height, 0), shade(cup, 0.06), M.SmoothPlastic)
		column(f, "CupRim", 0.6, width * 0.92, base + Vector3.new(0, height + 1, 0), rim, M.Glass).Transparency = 0.3
	end
	for ledge = 1, #H.LedgeDepths do
		for _ = 1, 6 do
			local base = ledgePoint(layer, ledge, rng:NextNumber(0, TAU), rng:NextNumber(0.55, 0.9))
			cupTree(base, rng:NextNumber(14, 26), rng:NextNumber(10, 16))
		end
	end
	-- Giants rising from the lower ledge, as in the chart.
	for _ = 1, 4 do
		local base = ledgePoint(layer, 2, rng:NextNumber(0, TAU), 0.85)
		cupTree(base, rng:NextNumber(70, 95), rng:NextNumber(24, 30))
	end

	-- Ice crystal clusters on the walls and ledges.
	local crystalColors = { Color3.fromRGB(215, 240, 255), Color3.fromRGB(160, 220, 255), Color3.fromRGB(175, 150, 235) }
	for i = 1, 20 do
		local angle = rng:NextNumber(0, TAU)
		local onLedge = i % 2 == 0
		local base = if onLedge
			then ledgePoint(layer, rng:NextInteger(1, 2), angle, rng:NextNumber(0.7, 1))
			else wallPoint(layerTop(layer) + rng:NextNumber(8, H.LayerHeight - 8), angle, 0)
		local color = crystalColors[rng:NextInteger(1, #crystalColors)]
		local first
		for _ = 1, 3 do
			local target = base + inward(angle) * rng:NextNumber(2, 6) + Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(3, 8), rng:NextNumber(-3, 3))
			local crystal = spike(f, "Crystal", base, target, rng:NextNumber(1.4, 3), rng:NextNumber(6, 16), color, M.Glass)
			crystal.Transparency = 0.2
			crystal.Reflectance = 0.1
			first = first or crystal
		end
		if i % 3 == 0 then
			light(first, color, 30, 1.6)
		end
	end
end

local function drownedTerraces(f: Folder)
	local layer = 5
	-- Water spilling over each ledge's inner edge to the level below.
	for ledge = 1, #H.LedgeDepths do
		local from = ledgeDepth(layer, ledge)
		local to = if ledge < #H.LedgeDepths then ledgeDepth(layer, ledge + 1) else ledgeDepth(layer + 1, 1)
		for _ = 1, 5 do
			local angle = betweenRopes()
			local lipPoint = polar(H.LedgeInnerRadius + 2, angle, rimY - from + 1)
			waterfall(f, lipPoint, to - from - 1, rng:NextNumber(6, 10), ledge == 1)
		end
		for _ = 1, 2 do
			lantern(f, ledgePoint(layer, ledge, rng:NextNumber(0, TAU), 0.97) + Vector3.new(0, 5, 0), Color3.fromRGB(140, 220, 230))
		end
	end
	-- Falls down the walls feeding the pools.
	for i = 0, 3 do
		waterfall(f, wallPoint(layerTop(layer), (i / 4) * TAU + math.rad(30), 2), H.LedgeDepths[1], 12)
	end
	-- Stepped stone terraces against the wall.
	for _ = 1, 8 do
		local angle = rng:NextNumber(0, TAU)
		local ledge = rng:NextInteger(1, 2)
		local base = ledgePoint(layer, ledge, angle, 0.95)
		local facing = CFrame.lookAt(base, base + inward(angle))
		for step = 0, 2 do
			prop(f, "Terrace", Vector3.new(10 - step * 2, 2, 4), facing * CFrame.new(0, 1 + step * 2, -step * 1.5), shade(Color3.fromRGB(80, 95, 100), 0.06), M.Slate)
		end
	end
end

local function rootboundRuins(f: Folder)
	local layer = 6
	local top = layerTop(layer)
	-- Giant roots crawling down the walls.
	for _ = 1, 16 do
		local angle = rng:NextNumber(0, TAU)
		local depth = top + rng:NextNumber(0, H.LayerHeight - 60)
		local a = wallPoint(depth, angle, -3)
		local b = wallPoint(depth + rng:NextNumber(40, 100), angle + rng:NextNumber(-0.22, 0.22), -1)
		strand(f, "Root", a, b, rng:NextNumber(3, 6), shade(Color3.fromRGB(85, 62, 42), 0.05), M.Wood)
	end
	-- Broken buildings on the ledges.
	local stone = { Color3.fromRGB(150, 140, 125), Color3.fromRGB(125, 115, 105), Color3.fromRGB(165, 150, 130) }
	for i = 1, 12 do
		local angle = rng:NextNumber(0, TAU)
		local ledge = (i % 2) + 1
		local base = ledgePoint(layer, ledge, angle, rng:NextNumber(0.6, 0.9))
		local facing = CFrame.lookAt(base, base + inward(angle)) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0)
		local w, h = rng:NextNumber(7, 11), rng:NextNumber(6, 13)
		local color = stone[rng:NextInteger(1, #stone)]
		prop(f, "Ruin", Vector3.new(w, h, 7), facing * CFrame.new(0, h / 2, 0), color, M.Brick)
		prop(f, "RuinBroken", Vector3.new(w * 0.6, 3, 5), facing * CFrame.new(w * 0.2, h + 1, 0) * CFrame.Angles(0, 0, rng:NextNumber(0.2, 0.5)), shade(color, 0.05), M.Brick)
		column(f, "Pillar", rng:NextNumber(6, 11), 1.6, (facing * CFrame.new(-w / 2 - 2, 4, -3)).Position, shade(color, 0.05), M.Concrete)
		prop(f, "Slab", Vector3.new(7, 1, 3), facing * CFrame.new(w / 2 + 3, 0.6, -2) * CFrame.Angles(0.15, 0.6, 0), shade(color, 0.05), M.Concrete)
		if i % 4 == 0 then
			local window = prop(f, "Window", Vector3.new(1.6, 2, 0.2), facing * CFrame.new(0, h * 0.6, -3.6), Color3.fromRGB(255, 180, 90), M.Neon)
			window.Transparency = 0.3
		end
	end
	-- Old machinery half sunk into the wall.
	for _ = 1, 4 do
		local angle = rng:NextNumber(0, TAU)
		local depth = top + rng:NextNumber(20, H.LayerHeight - 20)
		local hub = wallPoint(depth, angle, 0)
		prop(f, "Gear", Vector3.new(1.6, 14, 14), CFrame.lookAt(hub, hub + inward(angle)) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(110, 105, 100), M.CorrodedMetal, Enum.PartType.Cylinder)
	end
	for ledge = 1, #H.LedgeDepths do
		for _ = 1, 3 do
			lantern(f, ledgePoint(layer, ledge, rng:NextNumber(0, TAU), 0.97) + Vector3.new(0, 5, 0), Color3.fromRGB(255, 170, 90))
		end
	end
end

local function marrow(f: Folder)
	local layer = 7
	local top = layerTop(layer)
	local flesh = { Color3.fromRGB(215, 170, 140), Color3.fromRGB(200, 140, 120), Color3.fromRGB(230, 200, 160) }
	-- Fibrous strands along the walls.
	for _ = 1, 26 do
		local angle = rng:NextNumber(0, TAU)
		local depth = top + rng:NextNumber(0, H.LayerHeight - 30)
		local a = wallPoint(depth, angle, -1)
		local b = wallPoint(depth + rng:NextNumber(30, 110), angle + rng:NextNumber(-0.2, 0.2), -0.5)
		strand(f, "Fiber", a, b, rng:NextNumber(0.8, 2), flesh[rng:NextInteger(1, #flesh)])
	end
	-- Glowing pods set into the walls.
	for i = 1, 14 do
		local angle = rng:NextNumber(0, TAU)
		local depth = top + rng:NextNumber(10, H.LayerHeight - 10)
		local size = rng:NextNumber(7, 13)
		local position = wallPoint(depth, angle, size * 0.25)
		local shell = ball(f, "PodShell", size, position, Color3.fromRGB(210, 240, 110), M.Glass)
		shell.Transparency = 0.35
		local core = ball(f, "PodCore", size * 0.55, position, Color3.fromRGB(240, 255, 150), M.Neon)
		if i <= 10 then
			light(core, Color3.fromRGB(220, 255, 120), 28, 2)
		end
	end
end

-- A falling sheet of lava: like waterfall(), glowing orange and slower.
local function lavafall(parent: Instance, top: Vector3, length: number, width: number)
	local toCenter = Vector3.new(center.X - top.X, 0, center.Z - top.Z)
	local facing = if toCenter.Magnitude > 0.1 then CFrame.lookAt(top, top + toCenter) else CFrame.new(top)
	local lip = prop(parent, "Lavafall", Vector3.new(width, 1, 1.5), facing, Color3.fromRGB(255, 120, 30), M.Neon)
	local a0 = Instance.new("Attachment")
	a0.Parent = lip
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -length, 0)
	a1.Parent = lip
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.Width0 = width
	beam.Width1 = width * 1.1
	beam.Texture = SMOKE
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 18
	beam.TextureSpeed = 0.5
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 70, 20))
	beam.Transparency = NumberSequence.new(0.05, 0.25)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 1
	beam.Parent = lip
	light(lip, Color3.fromRGB(255, 120, 40), 40, 2)
end

-- Sparks or motes rising from a hidden holder.
local function rising(parent: Instance, position: Vector3, color: Color3, rate: number, spread: number)
	local holder = prop(parent, "Sparks", Vector3.one, CFrame.new(position), color)
	holder.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Lifetime = NumberRange.new(3, 6)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(3, 7)
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = holder
end

local function emberdeep(f: Folder)
	local layer = 8
	local top = layerTop(layer)
	local ember = Color3.fromRGB(255, 120, 40)
	-- Lava pouring down the walls onto the first ledge, and on to the second.
	for i = 0, 5 do
		local angle = (i / 6) * TAU + math.rad(15)
		lavafall(f, wallPoint(top, angle, 2), H.LedgeDepths[1], rng:NextNumber(6, 10))
	end
	for _ = 1, 3 do
		lavafall(f, wallPoint(ledgeDepth(layer, 1), rng:NextNumber(0, TAU), 1.5), H.LedgeDepths[2] - H.LedgeDepths[1], rng:NextNumber(5, 8))
	end
	-- Glowing magma veins cracking the walls.
	for _ = 1, 22 do
		local angle = rng:NextNumber(0, TAU)
		local depth = top + rng:NextNumber(4, H.LayerHeight - 30)
		local a = wallPoint(depth, angle, -0.3)
		local b = wallPoint(depth + rng:NextNumber(12, 34), angle + rng:NextNumber(-0.08, 0.08), -0.3)
		strand(f, "MagmaVein", a, b, rng:NextNumber(0.5, 1.1), ember, M.Neon)
	end
	-- Old furnaces with glowing mouths and chimneys on the ledges.
	for i = 1, 10 do
		local angle = rng:NextNumber(0, TAU)
		local base = ledgePoint(layer, (i % 2) + 1, angle, rng:NextNumber(0.65, 0.9))
		local facing = CFrame.lookAt(base, base + inward(angle))
		local brick = shade(Color3.fromRGB(70, 52, 46), 0.05)
		prop(f, "Furnace", Vector3.new(8, 7, 7), facing * CFrame.new(0, 3.5, 0), brick, M.Brick)
		local mouth = prop(f, "FurnaceMouth", Vector3.new(3.6, 2.6, 0.3), facing * CFrame.new(0, 2.6, -3.55), ember, M.Neon)
		column(f, "Chimney", 14, 2.4, (facing * CFrame.new(2, 14, 1.5)).Position, shade(brick, 0.04), M.Brick)
		prop(f, "ChimneyCap", Vector3.new(3.4, 0.6, 3.4), facing * CFrame.new(2, 21.3, 1.5), Color3.fromRGB(150, 110, 60), M.CorrodedMetal)
		if i % 2 == 0 then
			rising(f, (facing * CFrame.new(2, 22, 1.5)).Position, ember, 4, 15)
		end
		if i % 3 == 0 then
			light(mouth, ember, 26, 1.6)
		end
	end
	-- Brass steam pipes running down the walls.
	for _ = 1, 10 do
		local angle = rng:NextNumber(0, TAU)
		local depth = top + rng:NextNumber(0, H.LayerHeight - 70)
		local a = wallPoint(depth, angle, 1)
		local b = wallPoint(depth + rng:NextNumber(40, 70), angle, 1)
		strand(f, "Pipe", a, b, rng:NextNumber(1.6, 2.4), Color3.fromRGB(176, 136, 72), M.Metal)
		ball(f, "PipeValve", 3, (a + b) / 2, Color3.fromRGB(130, 96, 52), M.CorrodedMetal)
	end
	for ledge = 1, #H.LedgeDepths do
		for _ = 1, 2 do
			lantern(f, ledgePoint(layer, ledge, rng:NextNumber(0, TAU), 0.97) + Vector3.new(0, 5, 0), Color3.fromRGB(255, 150, 70))
		end
	end
end

local function gloamcap(f: Folder)
	local layer = 9
	local top = layerTop(layer)
	local glows = { Color3.fromRGB(170, 120, 255), Color3.fromRGB(120, 255, 210), Color3.fromRGB(255, 130, 230) }
	local stemColor = Color3.fromRGB(205, 190, 220)
	local function mushroom(base: Vector3, height: number, width: number, lit: boolean)
		local glow = glows[rng:NextInteger(1, #glows)]
		column(f, "Stem", height, math.max(1.2, width / 6), base + Vector3.new(0, height / 2, 0), shade(stemColor, 0.05), M.SmoothPlastic)
		local capPosition = base + Vector3.new(0, height, 0)
		local cap = prop(f, "Cap", Vector3.new(width, width * 0.38, width), CFrame.new(capPosition), shade(Color3.fromRGB(95, 60, 140), 0.06), M.SmoothPlastic, Enum.PartType.Ball)
		local gills = column(f, "Gills", 0.4, width * 0.9, capPosition - Vector3.new(0, width * 0.1, 0), glow, M.Neon)
		gills.Transparency = 0.2
		for _ = 1, 4 do
			local a = rng:NextNumber(0, TAU)
			local spot = capPosition + Vector3.new(math.cos(a) * width * 0.25, width * 0.15, math.sin(a) * width * 0.25)
			ball(f, "Spot", width * rng:NextNumber(0.08, 0.14), spot, glow, M.Neon)
		end
		if lit then
			light(cap, glow, width * 2.2, 1.8)
		end
	end
	for ledge = 1, #H.LedgeDepths do
		for i = 1, 8 do
			local base = ledgePoint(layer, ledge, rng:NextNumber(0, TAU), rng:NextNumber(0.55, 0.92))
			mushroom(base, rng:NextNumber(5, 14), rng:NextNumber(5, 11), i % 3 == 0)
		end
	end
	-- Giant mushrooms rising from the lower ledge.
	for _ = 1, 4 do
		local base = ledgePoint(layer, 2, rng:NextNumber(0, TAU), 0.88)
		mushroom(base, rng:NextNumber(45, 70), rng:NextNumber(22, 30), true)
	end
	-- Shelf fungi stepping up the walls.
	for _ = 1, 18 do
		local angle = rng:NextNumber(0, TAU)
		local depth = top + rng:NextNumber(6, H.LayerHeight - 6)
		local width = rng:NextNumber(4, 8)
		local shelf = column(f, "ShelfFungus", 0.8, width, wallPoint(depth, angle, width * 0.3), shade(glows[rng:NextInteger(1, #glows)], 0.1), M.Neon)
		shelf.Transparency = 0.25
	end
	-- Glowing tendrils hanging down the walls.
	for _ = 1, 16 do
		local angle = rng:NextNumber(0, TAU)
		local depth = top + rng:NextNumber(0, H.LayerHeight - 40)
		local a = wallPoint(depth, angle, 0.5)
		strand(f, "Tendril", a, a - Vector3.new(0, rng:NextNumber(10, 26), 0), rng:NextNumber(0.3, 0.6), glows[rng:NextInteger(1, #glows)], M.Neon)
	end
	for i = 1, 4 do
		mist(f, ledgePoint(layer, (i % 2) + 1, rng:NextNumber(0, TAU), 0.8) + Vector3.new(0, 3, 0), 14, 2, Color3.fromRGB(150, 110, 220))
	end
end

local function lumenCore(f: Folder)
	local layer = 10
	local top = layerTop(layer)
	local pale, gold = Color3.fromRGB(250, 246, 232), Color3.fromRGB(255, 220, 140)
	-- Pale crystal spires on the ledges.
	for i = 1, 18 do
		local angle = rng:NextNumber(0, TAU)
		local base = ledgePoint(layer, (i % 2) + 1, angle, rng:NextNumber(0.6, 1))
		local first
		for _ = 1, 3 do
			local target = base + inward(angle) * rng:NextNumber(1, 4) + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(6, 10), rng:NextNumber(-2, 2))
			local crystal = spike(f, "Spire", base, target, rng:NextNumber(1.4, 2.8), rng:NextNumber(8, 22), shade(pale, 0.04), M.Glass)
			crystal.Transparency = 0.15
			first = first or crystal
		end
		if i % 3 == 0 then
			light(first, gold, 30, 1.8)
		end
	end
	-- Floating stones with glowing seams near the walls.
	for i = 1, 14 do
		local angle = rng:NextNumber(0, TAU)
		local depth = top + rng:NextNumber(10, H.LayerHeight - 20)
		local size = rng:NextNumber(4, 9)
		local cframe = CFrame.new(wallPoint(depth, angle, size + 6)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, TAU), 0)
		local stone = prop(f, "FloatingStone", Vector3.new(size, size * 0.7, size), cframe, shade(Color3.fromRGB(225, 218, 200), 0.05), M.Limestone)
		prop(f, "Seam", Vector3.new(size * 1.02, 0.3, size * 1.02), cframe, gold, M.Neon)
		if i % 4 == 0 then
			light(stone, gold, 24, 1.4)
		end
	end
	-- Golden light running up the walls.
	for i = 0, 7 do
		local angle = (i / 8) * TAU + math.rad(10)
		strand(f, "LightVein", wallPoint(top + H.LayerHeight - 4, angle, -0.3), wallPoint(top + 6, angle + 0.05, -0.3), 0.6, gold, M.Neon)
	end
	-- The light at the very bottom: a glowing core half sunk in the floor, with motes
	-- drifting up out of it and light roots running to it from the walls.
	local floor = rimY - #Config.Layers * H.LayerHeight
	local core = ball(f, "LumenCore", 38, Vector3.new(center.X, floor - 4, center.Z), Color3.fromRGB(255, 244, 205), M.Neon)
	light(core, gold, 60, 3)
	ball(f, "LumenHalo", 46, core.Position, gold, M.Glass).Transparency = 0.75
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 240, 180))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.7, 0)
	emitter.Lifetime = NumberRange.new(6, 10)
	emitter.Rate = 8
	emitter.Speed = NumberRange.new(3, 7)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = core
	for i = 0, 9 do
		local angle = i / 10 * TAU
		strand(f, "LightRoot", wallPoint(H.LayerHeight * #Config.Layers - 2, angle, 0), polar(18, angle + 0.3, floor + 0.5), rng:NextNumber(0.6, 1.2), gold, M.Neon)
	end
end

local BUILDERS = { gardens, hangingWood, veilfall, glasswood, drownedTerraces, rootboundRuins, marrow, emberdeep, gloamcap, lumenCore }

function DevDecor.build(map: Instance, theCenter: Vector3)
	center = theCenter
	rimY = theCenter.Y
	rng = Random.new(1337)

	buildTown(map)
	DevBase.buildTown(map, center)
	local hollowDecor = folder(map, "HollowDecor")
	for layer, builder in BUILDERS do
		local name = Config.Layers[layer].name:gsub("[^%w]", "")
		builder(folder(hollowDecor, string.format("Layer%d_%s", layer, name)))
	end
end

return DevDecor
