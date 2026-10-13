--[[
	Builds the Hollow's creatures (Config.Enemies.Kinds) from parts, each styled to its
	layer:

	  hopper   Mosshopper          a round mossy hopper with leaf ears (Mistfall Gardens)
	  crawler  Barkcrawler         a bark spider with six legs and red eyes (Hanging Wood)
	  wraith   Spray Wraith        a floating mist spirit with blue eyes (Veilfall Cliffs)
	  beetle   Shardback           an ice beetle with glowing crystal spines (Glasswood)
	  fin      Murkfin             a waddling fish with fins and yellow eyes (Drowned)
	  golem    Clockwork Sentinel  a brass golem with a gear chest (Rootbound Ruins)
	  wyrm     Marrow Wyrm         a pale segmented crawler with glowing pods (The Marrow)
	  crab     Slagcrab            a basalt crab with glowing cracks and claws (Emberdeep)
	  stalker  Gloam Stalker       a walking mushroom with a glowing cap (Gloamcap Grotto)
	  seraph   Lumen Seraph        a floating core inside a ring of gilded wings (Lumen Core)

	Every model: anchored, non-colliding parts; an invisible HumanoidRootPart; a Head;
	a Humanoid for health (health bar shows once damaged). Built around the origin with
	the feet at y = 0 and the face toward -Z; the model's pivot is that ground point, so
	PivotTo places it standing on a spot.
]]

local EnemyModels = {}

local M = Enum.Material
local BLACK = Color3.fromRGB(20, 18, 16)

type Ctx = {
	add: (shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, name: string?) -> BasePart,
	kind: any,
}

local function shade(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local BUILDERS: { [string]: (Ctx) -> number } = {} -- each returns the creature's height

function BUILDERS.hopper(c)
	local k = c.kind
	c.add(Enum.PartType.Ball, Vector3.new(3.4, 3, 3.4), CFrame.new(0, 1.7, 0), k.body, M.Grass, "Head")
	c.add(Enum.PartType.Ball, Vector3.new(2.4, 1.2, 2.4), CFrame.new(0, 2.9, 0.2), shade(k.body, 0.15), M.Grass)
	for _, x in { -0.8, 0.8 } do
		c.add(Enum.PartType.Ball, Vector3.new(0.8, 0.8, 0.8), CFrame.new(x, 2.3, -1.45), Color3.new(1, 1, 1), M.SmoothPlastic)
		c.add(Enum.PartType.Ball, Vector3.new(0.4, 0.4, 0.4), CFrame.new(x, 2.3, -1.8), BLACK, M.SmoothPlastic)
		c.add(Enum.PartType.Block, Vector3.new(0.3, 1.6, 0.9), CFrame.new(x * 1.5, 3.4, 0) * CFrame.Angles(0, 0, x * 0.6), k.accent, M.Grass)
		c.add(Enum.PartType.Ball, Vector3.new(1.1, 0.7, 1.6), CFrame.new(x * 1.3, 0.35, 0.6), shade(k.body, 0.2), M.Grass)
	end
	return 3.6
end

function BUILDERS.crawler(c)
	local k = c.kind
	c.add(Enum.PartType.Ball, Vector3.new(3, 1.8, 3.6), CFrame.new(0, 2, 0.6), k.body, M.Wood)
	c.add(Enum.PartType.Ball, Vector3.new(1.8, 1.5, 1.8), CFrame.new(0, 1.9, -1.6), shade(k.body, 0.2), M.Wood, "Head")
	for _, x in { -0.4, 0.4 } do
		c.add(Enum.PartType.Ball, Vector3.new(0.35, 0.35, 0.35), CFrame.new(x, 2.2, -2.45), k.accent, M.Neon)
	end
	for i = 0, 2 do
		for _, side in { -1, 1 } do
			local z = -0.6 + i * 1.1
			-- Upper leg out and up, lower leg down to the ground.
			c.add(Enum.PartType.Block, Vector3.new(1.8, 0.3, 0.3), CFrame.new(side * 1.8, 2.4, z) * CFrame.Angles(0, 0, side * -0.5), shade(k.body, 0.3), M.Wood)
			c.add(Enum.PartType.Block, Vector3.new(0.3, 2.4, 0.3), CFrame.new(side * 2.7, 1.2, z) * CFrame.Angles(0, 0, side * 0.25), shade(k.body, 0.35), M.Wood)
		end
	end
	return 3
end

function BUILDERS.wraith(c)
	local k = c.kind
	for i, size in { 2.6, 2.2, 1.6, 1 } do
		local p = c.add(Enum.PartType.Ball, Vector3.new(size, size * 1.1, size), CFrame.new(0, 1.2 + i * 0.9, 0), k.body, M.Glass, if i == 1 then "Head" else nil)
		p.Transparency = 0.25 + i * 0.1
	end
	local head = c.add(Enum.PartType.Ball, Vector3.new(2, 2, 2), CFrame.new(0, 4.6, -0.2), k.body, M.SmoothPlastic)
	head.Transparency = 0.15
	for _, x in { -0.4, 0.4 } do
		c.add(Enum.PartType.Ball, Vector3.new(0.45, 0.3, 0.3), CFrame.new(x, 4.7, -1.1), k.accent, M.Neon)
	end
	for _, x in { -1, 1 } do
		local arm = c.add(Enum.PartType.Block, Vector3.new(0.4, 2.2, 0.4), CFrame.new(x * 1.4, 3.2, -0.4) * CFrame.Angles(-0.6, 0, x * 0.4), k.body, M.Glass)
		arm.Transparency = 0.4
	end
	return 5.6
end

function BUILDERS.beetle(c)
	local k = c.kind
	c.add(Enum.PartType.Ball, Vector3.new(3.2, 1.8, 4.2), CFrame.new(0, 1.6, 0.4), k.body, M.Glass)
	c.add(Enum.PartType.Ball, Vector3.new(1.8, 1.4, 1.6), CFrame.new(0, 1.5, -2), shade(k.body, 0.25), M.Ice, "Head")
	for _, x in { -0.45, 0.45 } do
		c.add(Enum.PartType.Ball, Vector3.new(0.35, 0.35, 0.35), CFrame.new(x, 1.8, -2.75), k.accent, M.Neon)
		c.add(Enum.PartType.Block, Vector3.new(0.25, 0.25, 1.2), CFrame.new(x, 1.2, -3) * CFrame.Angles(0.3, x * 0.6, 0), k.accent, M.Glass)
	end
	for i, offset in { Vector3.new(0, 2.7, -0.4), Vector3.new(-0.7, 2.5, 0.6), Vector3.new(0.7, 2.5, 0.6), Vector3.new(0, 2.6, 1.5) } do
		c.add(Enum.PartType.Block, Vector3.new(0.45, 1.8, 0.45), CFrame.new(offset) * CFrame.Angles(0.3 * i - 0.5, i, 0.25 * (i % 2 * 2 - 1)), k.accent, M.Neon)
	end
	for i = 0, 2 do
		for _, side in { -1, 1 } do
			c.add(Enum.PartType.Block, Vector3.new(0.25, 1.6, 0.25), CFrame.new(side * 1.6, 0.7, -0.8 + i * 1.2) * CFrame.Angles(0, 0, side * 0.5), shade(k.body, 0.4), M.Ice)
		end
	end
	return 3.4
end

function BUILDERS.fin(c)
	local k = c.kind
	c.add(Enum.PartType.Ball, Vector3.new(2.6, 3.2, 3.6), CFrame.new(0, 2.6, 0), k.body, M.SmoothPlastic, "Head")
	c.add(Enum.PartType.Ball, Vector3.new(2, 1.2, 2.6), CFrame.new(0, 1.9, -0.3), shade(k.accent, 0.5), M.SmoothPlastic)
	for _, x in { -0.9, 0.9 } do
		c.add(Enum.PartType.Ball, Vector3.new(0.6, 0.6, 0.6), CFrame.new(x, 3.3, -1.5), k.accent, M.Neon)
		c.add(Enum.PartType.Block, Vector3.new(0.2, 1.4, 1.2), CFrame.new(x * 1.5, 2.6, 0.2) * CFrame.Angles(0.3, 0, x * 0.5), shade(k.body, 0.25), M.SmoothPlastic)
		c.add(Enum.PartType.Block, Vector3.new(0.6, 1.4, 0.6), CFrame.new(x * 0.7, 0.7, 0.3), shade(k.body, 0.3), M.SmoothPlastic)
	end
	c.add(Enum.PartType.Block, Vector3.new(0.25, 1.6, 1.4), CFrame.new(0, 4.3, 0.4), shade(k.body, 0.2), M.SmoothPlastic)
	c.add(Enum.PartType.Block, Vector3.new(0.25, 1.6, 1.4), CFrame.new(0, 2.6, 2.2) * CFrame.Angles(0.5, 0, 0), shade(k.body, 0.2), M.SmoothPlastic)
	return 4.4
end

function BUILDERS.golem(c)
	local k = c.kind
	c.add(Enum.PartType.Block, Vector3.new(3, 2.8, 2), CFrame.new(0, 3.6, 0), k.body, M.Metal)
	c.add(Enum.PartType.Block, Vector3.new(1.6, 1.4, 1.5), CFrame.new(0, 5.7, 0), shade(k.body, 0.15), M.Metal, "Head")
	c.add(Enum.PartType.Ball, Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 5.8, -0.75), k.accent, M.Neon)
	local face = CFrame.Angles(0, math.pi / 2, 0)
	c.add(Enum.PartType.Cylinder, Vector3.new(0.3, 1.8, 1.8), CFrame.new(0, 3.7, -1.05) * face, shade(k.body, 0.3), M.Metal)
	c.add(Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 3.7, -1.2), k.accent, M.Neon)
	for _, x in { -1, 1 } do
		c.add(Enum.PartType.Block, Vector3.new(0.9, 3, 0.9), CFrame.new(x * 2, 3.3, 0) * CFrame.Angles(0, 0, x * 0.1), shade(k.body, 0.2), M.Metal)
		c.add(Enum.PartType.Block, Vector3.new(1.1, 2.2, 1.1), CFrame.new(x * 0.8, 1.1, 0), shade(k.body, 0.3), M.Metal)
	end
	return 6.4
end

function BUILDERS.wyrm(c)
	local k = c.kind
	for i = 0, 4 do
		local size = 2.6 - i * 0.3
		c.add(Enum.PartType.Ball, Vector3.new(size, size, size), CFrame.new(0, size / 2 + 0.1 + math.sin(i) * 0.3, -1.8 + i * 1.6), k.body, M.Marble, if i == 0 then "Head" else nil)
		if i > 0 then
			c.add(Enum.PartType.Ball, Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, size + 0.1, -1.8 + i * 1.6), k.accent, M.Neon)
		end
	end
	for _, x in { -0.5, 0.5 } do
		c.add(Enum.PartType.Block, Vector3.new(0.3, 0.3, 1.2), CFrame.new(x, 1.1, -3.2) * CFrame.Angles(0, -x * 0.8, 0), shade(k.body, 0.2), M.Marble)
		c.add(Enum.PartType.Ball, Vector3.new(0.35, 0.35, 0.35), CFrame.new(x * 0.8, 2.1, -2.8), k.accent, M.Neon)
	end
	return 2.8
end

function BUILDERS.crab(c)
	local k = c.kind
	c.add(Enum.PartType.Ball, Vector3.new(4, 1.8, 3.2), CFrame.new(0, 1.9, 0.2), k.body, M.Basalt)
	c.add(Enum.PartType.Block, Vector3.new(2.6, 0.12, 0.2), CFrame.new(0, 2.6, -0.4) * CFrame.Angles(0, 0.3, 0), k.accent, M.Neon)
	c.add(Enum.PartType.Block, Vector3.new(1.8, 0.12, 0.2), CFrame.new(0.3, 2.5, 0.8) * CFrame.Angles(0, -0.5, 0), k.accent, M.Neon)
	c.add(Enum.PartType.Ball, Vector3.new(1.4, 1, 1.2), CFrame.new(0, 2.1, -1.3), shade(k.body, 0.2), M.Basalt, "Head")
	for _, x in { -0.45, 0.45 } do
		c.add(Enum.PartType.Block, Vector3.new(0.18, 0.8, 0.18), CFrame.new(x, 2.8, -1.4), shade(k.body, 0.3), M.Basalt)
		c.add(Enum.PartType.Ball, Vector3.new(0.4, 0.4, 0.4), CFrame.new(x, 3.25, -1.4), k.accent, M.Neon)
	end
	for _, side in { -1, 1 } do
		-- A big claw on each side, glowing inside.
		c.add(Enum.PartType.Block, Vector3.new(0.5, 0.5, 1.6), CFrame.new(side * 2, 1.9, -1.4) * CFrame.Angles(0, side * 0.4, 0), shade(k.body, 0.15), M.Basalt)
		c.add(Enum.PartType.Ball, Vector3.new(1.3, 1, 1.5), CFrame.new(side * 2.4, 2, -2.4), k.body, M.Basalt)
		c.add(Enum.PartType.Block, Vector3.new(0.3, 0.2, 0.9), CFrame.new(side * 2.4, 2, -3.1), k.accent, M.Neon)
		for i = 0, 2 do
			c.add(Enum.PartType.Block, Vector3.new(0.25, 2, 0.25), CFrame.new(side * 2.1, 0.9, -0.2 + i * 0.9) * CFrame.Angles(0, 0, side * 0.6), shade(k.body, 0.35), M.Basalt)
		end
	end
	return 3.2
end

function BUILDERS.stalker(c)
	local k = c.kind
	c.add(Enum.PartType.Cylinder, Vector3.new(3.4, 1.6, 1.6), CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(205, 190, 220), M.SmoothPlastic)
	c.add(Enum.PartType.Ball, Vector3.new(4.6, 2, 4.6), CFrame.new(0, 4.6, 0), k.body, M.SmoothPlastic, "Head")
	c.add(Enum.PartType.Cylinder, Vector3.new(0.2, 4, 4), CFrame.new(0, 4.05, 0) * CFrame.Angles(0, 0, math.pi / 2), k.accent, M.Neon)
	for _, offset in { Vector3.new(0.9, 5.4, -0.6), Vector3.new(-1, 5.3, 0.5), Vector3.new(0.2, 5.6, 0.9), Vector3.new(-0.4, 5.5, -1.1) } do
		c.add(Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), CFrame.new(offset), k.accent, M.Neon)
	end
	for _, x in { -0.35, 0.35 } do
		c.add(Enum.PartType.Ball, Vector3.new(0.35, 0.35, 0.35), CFrame.new(x, 3.2, -0.75), k.accent, M.Neon)
	end
	for _, x in { -1, 1 } do
		c.add(Enum.PartType.Block, Vector3.new(0.6, 1.8, 0.6), CFrame.new(x * 0.6, 0.9, 0), shade(Color3.fromRGB(205, 190, 220), 0.2), M.SmoothPlastic)
		c.add(Enum.PartType.Block, Vector3.new(0.35, 2.4, 0.35), CFrame.new(x * 1.2, 2.4, -0.3) * CFrame.Angles(-0.4, 0, x * 0.3), shade(Color3.fromRGB(205, 190, 220), 0.15), M.SmoothPlastic)
	end
	return 5.6
end

function BUILDERS.seraph(c)
	local k = c.kind
	c.add(Enum.PartType.Ball, Vector3.new(2, 2, 2), CFrame.new(0, 3.4, 0), k.body, M.Neon, "Head")
	local halo = c.add(Enum.PartType.Ball, Vector3.new(2.8, 2.8, 2.8), CFrame.new(0, 3.4, 0), k.accent, M.Glass)
	halo.Transparency = 0.6
	c.add(Enum.PartType.Ball, Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 3.5, -1.2), Color3.fromRGB(255, 255, 255), M.Neon)
	-- A ring of gilded feathers around the core, and two great wings.
	for i = 0, 9 do
		local angle = i / 10 * 2 * math.pi
		c.add(Enum.PartType.Block, Vector3.new(0.3, 0.9, 0.3), CFrame.new(0, 3.4, 0) * CFrame.Angles(0, 0, angle) * CFrame.new(0, 2.1, 0), k.accent, M.Foil)
	end
	for _, side in { -1, 1 } do
		for j = 0, 2 do
			c.add(Enum.PartType.Block, Vector3.new(2.6 - j * 0.5, 0.2, 0.8), CFrame.new(side * (2.4 + j * 0.3), 3.9 + j * 0.5, 0.4) * CFrame.Angles(0, 0, side * (0.35 + j * 0.25)), shade(k.body, j * 0.06), M.Marble)
		end
	end
	c.add(Enum.PartType.Block, Vector3.new(0.2, 1.8, 0.2), CFrame.new(0, 1.6, 0), k.accent, M.Neon)
	return 5.2
end

-- Builds a creature of `kind` (an entry of Config.Enemies.Kinds).
function EnemyModels.build(kind): Model
	local model = Instance.new("Model")
	model.Name = kind.id
	local scale = kind.scale
	local head: BasePart? = nil
	local ctx: Ctx = {
		kind = kind,
		add = function(shape, size, cf, color, material, name)
			local p = Instance.new("Part")
			p.Name = name or "Part"
			p.Shape = shape
			p.Size = size * scale
			p.CFrame = cf - cf.Position + cf.Position * scale
			p.Color = color
			p.Material = material or M.SmoothPlastic
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CastShadow = false
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Parent = model
			if name == "Head" then
				head = p
			end
			return p
		end,
	}
	local height = (BUILDERS[kind.shape] or BUILDERS.hopper)(ctx) * scale

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.6, height, 2.6) * Vector3.new(scale, 1, scale)
	root.CFrame = CFrame.new(0, height / 2, 0)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root
	model.WorldPivot = CFrame.new() -- the ground point under the creature
	assert(head, `{kind.id} has no Head part`)

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = kind.health
	humanoid.Health = kind.health
	humanoid.DisplayName = kind.name
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.NameDisplayDistance = 50
	humanoid.HealthDisplayDistance = 50
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model

	if kind.shape == "wraith" then
		local mist = Instance.new("ParticleEmitter")
		mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
		mist.Rate = 6
		mist.Lifetime = NumberRange.new(1, 2)
		mist.Speed = NumberRange.new(0.5, 1.5)
		mist.Size = NumberSequence.new(1.5 * scale, 3 * scale)
		mist.Transparency = NumberSequence.new(0.6, 1)
		mist.Color = ColorSequence.new(kind.body)
		mist.Parent = root
	elseif kind.shape == "crab" or kind.shape == "seraph" then
		local motes = Instance.new("ParticleEmitter")
		motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		motes.Rate = 4
		motes.Lifetime = NumberRange.new(1, 2)
		motes.Speed = NumberRange.new(1, 3)
		motes.Size = NumberSequence.new(0.4 * scale, 0)
		motes.LightEmission = 1
		motes.Color = ColorSequence.new(kind.accent)
		motes.Parent = root
	end
	if kind.shape == "seraph" or kind.shape == "stalker" then
		local glow = Instance.new("PointLight")
		glow.Color = kind.accent
		glow.Range = 14
		glow.Brightness = 1.2
		glow.Parent = head
	end
	return model
end

return EnemyModels
