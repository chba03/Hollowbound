--[[
	Builds the small 3D model each relic shows in the world and on display pedestals.

	Each type's look comes from Config.RelicTypes: a shape (one of the builders below,
	modelled on the relic reference sheet), a main colour, an accent colour, and a
	material. The rarity tier adds a light, sparkles, and, for Divine and Godly, a beam
	of light visible from across the pit, and scales the model up a little.

	Cheap by design: 3 to 15 anchored parts per relic, no collisions, no shadows, no
	queries, no uploaded meshes. The model's PrimaryPart ("Core") is an invisible part at
	its centre; prompts attach to it and distance checks use it. Clients spin and bob
	models tagged Config.Tags.Spin (client RelicSpin).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))

local RelicModels = {}

local M = Enum.Material
local DARK = Color3.fromRGB(35, 35, 40)

type Builder = {
	add: (shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?) -> BasePart,
	ellipsoid: (size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?) -> BasePart,
	segment: (a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material?) -> BasePart,
	main: Color3,
	accent: Color3,
	material: Enum.Material,
}

-- Rotates a cylinder (axis X) so its axis points along `direction`.
local function along(position: Vector3, direction: Vector3): CFrame
	return CFrame.lookAt(position, position + direction) * CFrame.Angles(0, math.pi / 2, 0)
end

-- Shape builders: local coordinates, centred on the origin, about 2 studs across.
local SHAPES: { [string]: (b: Builder) -> () } = {}

-- Crystal block (the tall blue prism).
function SHAPES.prism(b)
	local tilt = CFrame.Angles(0, 0.4, 0.3)
	local shell = b.add(Enum.PartType.Block, Vector3.new(0.9, 2.2, 0.9), tilt, b.main, b.material)
	shell.Transparency = if b.material == M.Glass then 0.25 else 0
	b.add(Enum.PartType.Block, Vector3.new(0.35, 1.7, 0.35), tilt, b.accent, M.Neon)
end

-- String of beads with a short branch.
function SHAPES.beads(b)
	local points = {
		Vector3.new(-0.9, -0.8, 0),
		Vector3.new(-0.55, -0.5, 0.1),
		Vector3.new(-0.2, -0.25, 0),
		Vector3.new(0.1, 0.1, -0.1),
		Vector3.new(0.35, 0.45, 0),
		Vector3.new(0.6, 0.8, 0.1),
		Vector3.new(0.45, -0.05, 0.3),
		Vector3.new(0.8, -0.2, 0.4),
	}
	for index, point in points do
		local size = if index == 6 then 0.75 else 0.5 + (index % 3) * 0.06
		b.add(Enum.PartType.Ball, Vector3.new(size, size, size), CFrame.new(point), b.main, b.material)
	end
end

-- Ornate knotted plaque with four round bosses and a stem.
function SHAPES.knot(b)
	b.add(Enum.PartType.Block, Vector3.new(1.9, 1.1, 0.22), CFrame.new(), b.main, b.material)
	b.add(Enum.PartType.Block, Vector3.new(1.1, 1.5, 0.2), CFrame.Angles(0, 0, math.pi / 4), b.main, b.material)
	for _, offset in { Vector3.new(-0.75, 0.35, 0), Vector3.new(0.75, 0.35, 0), Vector3.new(-0.75, -0.35, 0), Vector3.new(0.75, -0.35, 0) } do
		b.add(Enum.PartType.Cylinder, Vector3.new(0.3, 0.5, 0.5), along(offset, Vector3.zAxis), b.accent, b.material)
	end
	b.ellipsoid(Vector3.new(0.7, 0.35, 0.3), CFrame.new(0, 0, 0.08), b.accent, M.Neon)
	b.add(Enum.PartType.Block, Vector3.new(0.25, 0.7, 0.18), CFrame.new(0, -0.9, 0), b.main, b.material)
end

-- Banded stone block (the striped rock).
function SHAPES.layered(b)
	local colors = { b.main, b.accent, DARK:Lerp(b.main, 0.4), b.accent:Lerp(b.main, 0.5) }
	for index = 1, 4 do
		local y = -0.75 + (index - 1) * 0.5
		b.add(Enum.PartType.Block, Vector3.new(1.5 - index * 0.05, 0.48, 1.1), CFrame.new(0.05 * (index % 2), y, 0) * CFrame.Angles(0, index * 0.08, 0.05 * (index % 2 * 2 - 1)), colors[index], b.material)
	end
end

-- Sphere wrapped in rings, with open ports.
function SHAPES.ringsphere(b)
	b.add(Enum.PartType.Ball, Vector3.new(1.6, 1.6, 1.6), CFrame.new(), b.main, b.material)
	for _, axis in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
		b.add(Enum.PartType.Cylinder, Vector3.new(0.14, 1.78, 1.78), along(Vector3.zero, axis), b.accent, b.material)
	end
	for _, direction in { Vector3.new(1, 1, 1).Unit, Vector3.new(-1, 1, -1).Unit, Vector3.new(1, -1, -1).Unit } do
		b.add(Enum.PartType.Cylinder, Vector3.new(0.12, 0.6, 0.6), along(direction * 0.76, direction), DARK, M.SmoothPlastic)
	end
	b.add(Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), CFrame.new(), b.accent, M.Neon).Transparency = 0.3
end

-- Stone disc with a central eye and a notch.
function SHAPES.disc(b)
	local face = Vector3.zAxis
	b.add(Enum.PartType.Cylinder, Vector3.new(0.3, 2.1, 2.1), along(Vector3.zero, face), b.main, b.material)
	b.add(Enum.PartType.Cylinder, Vector3.new(0.36, 1.2, 1.2), along(Vector3.zero, face), b.accent, b.material)
	b.add(Enum.PartType.Cylinder, Vector3.new(0.42, 0.5, 0.5), along(Vector3.zero, face), DARK, M.SmoothPlastic)
	b.add(Enum.PartType.Ball, Vector3.new(0.22, 0.22, 0.22), CFrame.new(0, 0, 0.2), b.accent, M.Neon)
	for i = 0, 5 do
		local angle = i * math.pi / 3
		b.add(Enum.PartType.Ball, Vector3.new(0.18, 0.18, 0.18), CFrame.new(math.cos(angle) * 0.82, math.sin(angle) * 0.82, 0.16), DARK, M.SmoothPlastic)
	end
end

-- Crossed, twisted staves (the wooden cross and key).
function SHAPES.cross(b)
	b.add(Enum.PartType.Block, Vector3.new(0.32, 2.2, 0.3), CFrame.Angles(0, 0, 0.35), b.main, b.material)
	b.add(Enum.PartType.Block, Vector3.new(0.32, 2.0, 0.3), CFrame.Angles(0, 0, -0.35), b.main, b.material)
	b.add(Enum.PartType.Block, Vector3.new(1.5, 0.22, 0.24), CFrame.new(0, 0.45, 0.05), b.accent, b.material)
	b.add(Enum.PartType.Block, Vector3.new(0.9, 0.2, 0.24), CFrame.new(0, -0.5, 0.05), b.accent, b.material)
	b.add(Enum.PartType.Block, Vector3.new(0.4, 0.4, 0.4), CFrame.Angles(0, 0, math.pi / 4), b.accent, b.material)
end

-- Coiled cage (the chain-link spiral).
function SHAPES.coil(b)
	local turns, links = 3.2, 15
	for i = 0, links - 1 do
		local t = i / (links - 1)
		local angle = t * turns * 2 * math.pi
		local radius = 0.65 - 0.12 * math.sin(t * math.pi)
		local position = Vector3.new(math.cos(angle) * radius, -1 + t * 2, math.sin(angle) * radius)
		local tangent = Vector3.new(-math.sin(angle), 0.18, math.cos(angle))
		b.add(Enum.PartType.Block, Vector3.new(0.18, 0.18, 0.62), CFrame.lookAt(position, position + tangent), if i % 2 == 0 then b.main else b.accent, b.material)
	end
end

-- Round pod with sunken spots and a curled fin.
function SHAPES.podball(b)
	b.add(Enum.PartType.Ball, Vector3.new(1.5, 1.5, 1.5), CFrame.new(), b.main, b.material)
	for _, direction in { Vector3.new(0, 1, 0.3), Vector3.new(0.8, 0.3, 0.5), Vector3.new(-0.7, 0.4, 0.6), Vector3.new(0.3, -0.4, 0.9), Vector3.new(-0.5, -0.5, -0.7) } do
		local n = direction.Unit
		b.add(Enum.PartType.Cylinder, Vector3.new(0.1, 0.38, 0.38), along(n * 0.72, n), b.accent, M.SmoothPlastic)
	end
	b.segment(Vector3.new(0.5, -0.5, -0.3), Vector3.new(0.95, -0.85, -0.6), 0.22, b.accent, b.material)
	b.segment(Vector3.new(0.95, -0.85, -0.6), Vector3.new(1.1, -0.4, -0.75), 0.16, b.accent, b.material)
end

-- Lumpy sphere with knobs and ridges.
function SHAPES.lumpball(b)
	b.add(Enum.PartType.Ball, Vector3.new(1.55, 1.55, 1.55), CFrame.new(), b.main, b.material)
	local directions = {
		Vector3.new(1, 0.4, 0.2), Vector3.new(-0.8, 0.6, 0.3), Vector3.new(0.2, -0.9, 0.5),
		Vector3.new(0.3, 0.8, -0.7), Vector3.new(-0.5, -0.4, -0.8), Vector3.new(0.6, -0.2, 0.9),
	}
	for index, direction in directions do
		local n = direction.Unit
		local size = 0.38 + (index % 3) * 0.06
		b.add(Enum.PartType.Ball, Vector3.new(size, size, size), CFrame.new(n * 0.72), b.accent, b.material)
	end
	b.add(Enum.PartType.Block, Vector3.new(1.7, 0.14, 0.3), CFrame.Angles(0.3, 0.5, 0.2), b.accent, b.material)
end

-- Spiked urn with a neck and eyes.
function SHAPES.spikeball(b)
	b.add(Enum.PartType.Ball, Vector3.new(1.5, 1.5, 1.5), CFrame.new(), b.main, b.material)
	b.add(Enum.PartType.Cylinder, Vector3.new(0.5, 0.75, 0.75), along(Vector3.new(0, 0.85, 0), Vector3.yAxis), b.accent, b.material)
	for _, direction in { Vector3.new(1, 0.2, 0), Vector3.new(-1, 0.1, 0.2), Vector3.new(0, -0.2, 1), Vector3.new(0.2, 0, -1), Vector3.new(0.6, -0.7, 0.4), Vector3.new(-0.5, -0.6, -0.5) } do
		local n = direction.Unit
		b.add(Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.55), CFrame.lookAt(n * 0.85, n * 2), b.main:Lerp(DARK, 0.25), b.material)
	end
	b.add(Enum.PartType.Ball, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0.35, 0.15, 0.62), DARK, M.SmoothPlastic)
	b.add(Enum.PartType.Ball, Vector3.new(0.2, 0.2, 0.2), CFrame.new(-0.2, 0.3, 0.66), b.accent, M.Neon)
end

-- Core wrapped in spiralling bands, with prongs on top.
function SHAPES.spiral(b)
	b.ellipsoid(Vector3.new(0.75, 1.9, 0.75), CFrame.new(), b.accent, M.Glass)
	for i = 0, 4 do
		b.add(Enum.PartType.Block, Vector3.new(1.0, 0.16, 0.9), CFrame.new(0, -0.75 + i * 0.38, 0) * CFrame.Angles(0, i * 1.2, 0.3), b.main, b.material)
	end
	b.segment(Vector3.new(0.1, 0.8, 0), Vector3.new(0.3, 1.35, 0.05), 0.14, b.main, b.material)
	b.segment(Vector3.new(-0.1, 0.8, 0), Vector3.new(-0.25, 1.3, -0.05), 0.12, b.main, b.material)
end

-- Curled horn with a round boss and a red eye (the hooked horn).
function SHAPES.hook(b)
	local points = {
		Vector3.new(-0.6, -0.4, 0),
		Vector3.new(0.0, -0.9, 0),
		Vector3.new(0.6, -0.7, 0),
		Vector3.new(0.85, -0.1, 0),
		Vector3.new(0.6, 0.6, 0),
		Vector3.new(0.1, 1.0, 0),
	}
	for index = 1, #points - 1 do
		b.segment(points[index], points[index + 1], 0.34 - index * 0.045, b.main, b.material)
	end
	b.add(Enum.PartType.Cylinder, Vector3.new(0.3, 0.9, 0.9), along(Vector3.new(-0.6, -0.4, 0), Vector3.zAxis), b.main:Lerp(DARK, 0.2), b.material)
	b.add(Enum.PartType.Ball, Vector3.new(0.3, 0.3, 0.3), CFrame.new(-0.6, -0.4, 0.15), b.accent, M.Neon)
end

-- Bone shaft curling into a forked hook.
function SHAPES.bonehook(b)
	local points = {
		Vector3.new(0, 1.0, 0),
		Vector3.new(0, 0.2, 0),
		Vector3.new(0.1, -0.6, 0),
		Vector3.new(0.5, -0.95, 0),
		Vector3.new(0.85, -0.7, 0),
		Vector3.new(0.85, -0.3, 0),
	}
	for index = 1, #points - 1 do
		b.segment(points[index], points[index + 1], 0.3, b.main, b.material)
	end
	b.add(Enum.PartType.Cylinder, Vector3.new(0.12, 0.36, 0.36), along(Vector3.new(0, -0.1, 0), Vector3.yAxis), b.accent, b.material)
	b.segment(Vector3.new(0, 1.0, 0), Vector3.new(-0.3, 1.35, 0), 0.18, b.main, b.material)
	b.segment(Vector3.new(0, 1.0, 0), Vector3.new(0.3, 1.4, 0), 0.18, b.main, b.material)
	b.segment(Vector3.new(0.85, -0.3, 0), Vector3.new(1.05, -0.05, 0), 0.16, b.main, b.material)
end

-- Bell with a rim, handle, and clapper.
function SHAPES.bell(b)
	b.ellipsoid(Vector3.new(1.3, 1.5, 1.3), CFrame.new(0, 0.1, 0), b.main, b.material)
	b.add(Enum.PartType.Cylinder, Vector3.new(0.25, 1.55, 1.55), along(Vector3.new(0, -0.45, 0), Vector3.yAxis), b.accent, b.material)
	b.add(Enum.PartType.Cylinder, Vector3.new(0.3, 0.4, 0.4), along(Vector3.new(0, 0.95, 0), Vector3.zAxis), b.accent, b.material)
	b.add(Enum.PartType.Ball, Vector3.new(0.35, 0.35, 0.35), CFrame.new(0, -0.75, 0), b.accent, M.Neon)
end

-- Folded, faceted cube with an eye (the green folded block).
function SHAPES.folded(b)
	b.add(Enum.PartType.Block, Vector3.new(1.25, 1.25, 1.25), CFrame.Angles(0.6, 0.7, 0.2), b.main, b.material)
	b.add(Enum.PartType.Block, Vector3.new(1.15, 1.15, 1.15), CFrame.Angles(-0.4, 0.2, 0.75), b.main:Lerp(b.accent, 0.25), b.material)
	b.add(Enum.PartType.Block, Vector3.new(1.4, 0.12, 1.0), CFrame.Angles(0.2, 0.5, 0.4), b.accent, b.material)
	b.add(Enum.PartType.Cylinder, Vector3.new(0.1, 0.42, 0.42), along(Vector3.new(0, 0.1, 0.78), Vector3.zAxis), b.accent, M.Neon)
end

local function tierOf(rarity: string)
	return Config.RarityById[rarity] or Config.Rarities[1]
end

local function addSparkles(core: BasePart, tier, extent: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Rate = tier.sparkle
	emitter.Lifetime = NumberRange.new(1.2, 2.2)
	emitter.Speed = NumberRange.new(0.4, 1.2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25 * extent), NumberSequenceKeypoint.new(1, 0) })
	emitter.LightEmission = 1
	emitter.Transparency = NumberSequence.new(0.2)
	if tier.id == "Godly" then
		-- Godly sparkles cycle through every colour.
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 230, 90)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 160)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(90, 170, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 120, 255)),
		})
	else
		emitter.Color = ColorSequence.new(tier.color)
	end
	emitter.Parent = core
end

-- Builds a relic model centred at `cframe`. `withBeacon` adds the tall light beam
-- for Divine and Godly relics (used in the Hollow, not on pedestals).
-- `size` is the specimen's size (already capped by the caller), on top of the tier scale.
function RelicModels.build(typeId: string, rarity: string, cframe: CFrame, withBeacon: boolean, size: number?): Model
	local relicType = Config.RelicTypes[typeId]
	local tier = tierOf(rarity)
	local scale = tier.scale * (size or 1)

	local model = Instance.new("Model")
	model.Name = typeId
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.new(1, 1, 1) * 2 * scale
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.CFrame = cframe
	core.Parent = model
	model.PrimaryPart = core

	local function finish(part: BasePart, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
		part.Size = size * scale
		part.CFrame = cframe * (offset - offset.Position + offset.Position * scale)
		part.Color = color
		part.Material = material or relicType.material
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		return part
	end

	local builder: Builder = {
		main = relicType.color,
		accent = relicType.accent,
		material = relicType.material,
		add = function(shape, size, offset, color, material)
			local part = Instance.new("Part")
			part.Shape = shape
			return finish(part, size, offset, color, material)
		end,
		ellipsoid = function(size, offset, color, material)
			local part = Instance.new("Part")
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
			return finish(part, size, offset, color, material)
		end,
		segment = function(a, b, thickness, color, material)
			local part = Instance.new("Part")
			part.Shape = Enum.PartType.Cylinder
			local length = (b - a).Magnitude
			return finish(part, Vector3.new(length + thickness * 0.6, thickness, thickness), along((a + b) / 2, b - a), color, material)
		end,
	}
	local shape = SHAPES[relicType.shape] or SHAPES.lumpball
	shape(builder)

	local light = Instance.new("PointLight")
	light.Color = tier.color
	-- On a pedestal (no beacon) the light is softer: the base is lit and close by.
	light.Range = if withBeacon then tier.light else tier.light * 0.6
	light.Brightness = if withBeacon then (if tier.rank >= 5 then 2 else 1.2) else 0.45
	light.Shadows = false
	light.Parent = core

	if tier.sparkle > 0 then
		addSparkles(core, tier, scale)
	end

	if withBeacon and tier.pillar then
		-- A thin beam of light rising from the relic, so a rare find shows across the pit.
		local beam = Instance.new("Part")
		beam.Name = "Beacon"
		beam.Shape = Enum.PartType.Cylinder
		beam.Size = Vector3.new(60, 0.6, 0.6)
		beam.CFrame = cframe * CFrame.new(0, 30, 0) * CFrame.Angles(0, 0, math.pi / 2)
		beam.Color = tier.color
		beam.Material = M.Neon
		beam.Transparency = 0.55
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
		beam.Parent = model
	end

	model:SetAttribute("HB_Base", cframe)
	CollectionService:AddTag(model, Config.Tags.Spin)
	return model
end

return RelicModels
