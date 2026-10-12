--[[
	DEVELOPMENT ONLY. The look of each player base and the town around it, after the
	base reference image supplied by the project owner: grassy cliff-top camps with a
	wooden display deck and rug, stone pedestals, rope coils, lantern posts, a tent and
	crates, a timber crane with pulleys and a big gear over the pit, and a wooden
	scaffold tower down the cliff below each base. Behind the bases: a timber-framed town
	with coloured roofs, windmills, ruined stone towers, and trees.

	Gameplay parts (Floor, Stand, RopeMount, RopeAnchor, Terminal, Pedestals, upgrade
	boards, Sign) are built by DevMap; this module only adds dressing around them, in a
	separate folder that is not Persistent, so distant bases can stream out.

	Performance: dressing is anchored, non-colliding, non-queryable, and shadowless,
	except the scaffold decks, deck, and fence, which players stand on or bump into.
	About 150 parts and 3 lights per base, about 650 parts for the town.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))

local DevBase = {}

local M = Enum.Material
local TAU = 2 * math.pi
local H = Config.Hollow

local WOOD = Color3.fromRGB(120, 86, 56)
local WOOD_DARK = Color3.fromRGB(86, 60, 40)
local WOOD_LIGHT = Color3.fromRGB(160, 120, 80)
local ROPE = Color3.fromRGB(196, 160, 106)
local CANVAS = Color3.fromRGB(196, 182, 140)
local RUST = Color3.fromRGB(130, 80, 50)
local STONE = Color3.fromRGB(150, 146, 138)
local LANTERN = Color3.fromRGB(255, 170, 80)
local WALKWAY_WIDTH = 3
-- Walkways end this far beside the rope line: close enough to grab the rope (F, within
-- Config.Rope.GrabRadius) but clear of a climber's body.
local WALKWAY_ROPE_GAP = 3.5

type At = (x: number, y: number, z: number) -> CFrame

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

-- A solid part players can stand on.
local function solid(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = prop(parent, name, size, cframe, color, material)
	p.CanCollide = true
	p.CanQuery = true
	p.CastShadow = true
	return p
end

-- A beam (block) from a to b.
local function beam(parent: Instance, name: string, a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material?): Part
	local length = (b - a).Magnitude
	return prop(parent, name, Vector3.new(thickness, thickness, length), CFrame.lookAt((a + b) / 2, b), color, material or M.Wood)
end

-- A round rope (cylinder) from a to b.
local function rope(parent: Instance, a: Vector3, b: Vector3, thickness: number)
	local length = (b - a).Magnitude
	prop(parent, "Rope", Vector3.new(length, thickness, thickness), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), ROPE, M.Fabric, Enum.PartType.Cylinder)
end

-- Cylinder whose axis runs along the CFrame's local X.
local function wheel(parent: Instance, name: string, diameter: number, width: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	return prop(parent, name, Vector3.new(width, diameter, diameter), cframe, color, material or M.Wood, Enum.PartType.Cylinder)
end

-- A gear: a disc with teeth, axis along the CFrame's local X.
local function gear(parent: Instance, diameter: number, cframe: CFrame)
	wheel(parent, "Gear", diameter, 0.6, cframe, RUST, M.CorrodedMetal)
	wheel(parent, "Hub", diameter * 0.3, 0.9, cframe, WOOD_DARK, M.Metal)
	local teeth = math.floor(diameter * 2.4)
	for i = 0, teeth - 1 do
		local angle = i / teeth * TAU
		prop(parent, "Tooth", Vector3.new(0.6, 0.5, 0.5), cframe * CFrame.Angles(angle, 0, 0) * CFrame.new(0, diameter / 2 + 0.15, 0), RUST, M.CorrodedMetal)
	end
	for i = 0, 3 do
		prop(parent, "Spoke", Vector3.new(0.4, diameter * 0.9, 0.35), cframe * CFrame.Angles(i * math.pi / 4, 0, 0), RUST, M.CorrodedMetal)
	end
end

-- A coil of rope lying on the ground at `cframe` (its base).
local function ropeCoil(parent: Instance, cframe: CFrame, diameter: number)
	local up = CFrame.Angles(0, 0, math.pi / 2)
	wheel(parent, "Coil", diameter, 0.45, cframe * CFrame.new(0, 0.23, 0) * up, ROPE, M.Fabric)
	wheel(parent, "Coil", diameter * 0.8, 0.45, cframe * CFrame.new(0.1, 0.6, 0) * up, ROPE:Lerp(WOOD, 0.15), M.Fabric)
	wheel(parent, "CoilHole", diameter * 0.38, 1.0, cframe * CFrame.new(0, 0.45, 0) * up, Color3.fromRGB(70, 60, 45), M.Fabric)
end

local function crate(parent: Instance, cframe: CFrame, size: number)
	local p = prop(parent, "Crate", Vector3.new(size, size, size), cframe * CFrame.new(0, size / 2, 0), WOOD_LIGHT, M.WoodPlanks)
	p.CastShadow = true
	prop(parent, "CrateBand", Vector3.new(size + 0.1, 0.3, size + 0.1), cframe * CFrame.new(0, size * 0.7, 0), WOOD_DARK, M.Wood)
end

local function barrel(parent: Instance, cframe: CFrame)
	wheel(parent, "Barrel", 2, 2.6, cframe * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.pi / 2), WOOD, M.Wood)
	wheel(parent, "Hoop", 2.1, 0.2, cframe * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), WOOD_DARK, M.Metal)
	wheel(parent, "Hoop", 2.1, 0.2, cframe * CFrame.new(0, 2.1, 0) * CFrame.Angles(0, 0, math.pi / 2), WOOD_DARK, M.Metal)
end

-- An A-frame canvas tent; `cframe` is the centre of its floor, ridge along local Z.
local function tent(parent: Instance, cframe: CFrame, width: number, height: number, length: number, color: Color3)
	local half = width / 2
	local left = Instance.new("WedgePart")
	local right = Instance.new("WedgePart")
	for _, wedge in { left, right } do
		wedge.Name = "Tent"
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.CanQuery = false
		wedge.CanTouch = false
		wedge.Size = Vector3.new(length, height, half)
		wedge.Color = color
		wedge.Material = M.Fabric
		wedge.Parent = parent
	end
	-- A wedge is tallest at its +Z face; turn each so that face sits on the ridge.
	left.CFrame = cframe * CFrame.new(-half / 2, height / 2, 0) * CFrame.Angles(0, math.pi / 2, 0)
	right.CFrame = cframe * CFrame.new(half / 2, height / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	prop(parent, "TentPole", Vector3.new(0.3, height + 0.6, 0.3), cframe * CFrame.new(0, (height + 0.6) / 2, length / 2), WOOD_DARK, M.Wood)
	prop(parent, "TentPole", Vector3.new(0.3, height + 0.6, 0.3), cframe * CFrame.new(0, (height + 0.6) / 2, -length / 2), WOOD_DARK, M.Wood)
end

-- A post with a hanging lantern; returns the lantern.
local function lanternPost(parent: Instance, base: CFrame, height: number, lit: boolean): Part
	prop(parent, "Post", Vector3.new(0.7, height, 0.7), base * CFrame.new(0, height / 2, 0), WOOD, M.Wood).CastShadow = true
	prop(parent, "PostCap", Vector3.new(1.4, 0.3, 0.3), base * CFrame.new(0.4, height - 0.4, 0), WOOD_DARK, M.Wood)
	local lantern = prop(parent, "Lantern", Vector3.new(0.6, 0.9, 0.6), base * CFrame.new(0.9, height - 1.2, 0), LANTERN, M.Neon)
	if lit then
		local light = Instance.new("PointLight")
		light.Color = LANTERN
		light.Range = 20
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = lantern
	end
	return lantern
end

-- Base dressing ------------------------------------------------------------------------

-- Display deck: plank floor with a rug and a timber border, corner lantern posts, and
-- rope railings. Pedestals (from DevMap) stand on it.
local function deck(f: Instance, at: At, accent: Color3)
	solid(f, "Deck", Vector3.new(40, 0.4, 24), at(0, 1.2, 11), WOOD, M.WoodPlanks)
	prop(f, "Rug", Vector3.new(34, 0.08, 18), at(0, 1.44, 11), accent, M.Fabric)
	prop(f, "RugBorder", Vector3.new(36, 0.06, 20), at(0, 1.42, 11), accent:Lerp(Color3.fromRGB(60, 30, 20), 0.5), M.Fabric)
	for _, edge in { { 0, -1, 40, 0.6 }, { 0, 23, 40, 0.6 }, { -20, 11, 0.6, 24 }, { 20, 11, 0.6, 24 } } do
		prop(f, "DeckBeam", Vector3.new(edge[3], 0.5, edge[4]), at(edge[1], 1.55, edge[2]), WOOD_DARK, M.Wood)
	end
	local corners = { { -20, -1 }, { 20, -1 }, { -20, 23 }, { 20, 23 } }
	for i, corner in corners do
		lanternPost(f, at(corner[1], 1.4, corner[2]), 6, i <= 2)
	end
	-- Rope railing along the sides and back.
	for _, pair in { { 1, 3 }, { 2, 4 }, { 3, 4 } } do
		local a, b = corners[pair[1]], corners[pair[2]]
		rope(f, at(a[1], 5, a[2]).Position, at(b[1], 5, b[2]).Position, 0.25)
	end
end

-- Timber crane over the pit: two legs, a crossbeam, braces, pulleys, a big gear by the
-- winch, and a rope from the winch drum up over the pulleys. DevMap's Arm and
-- RopeAnchor are the gameplay parts it carries.
local function crane(f: Instance, at: At, reach: number)
	local legHeight = 15
	for _, x in { -3.5, 3.5 } do
		prop(f, "CraneLeg", Vector3.new(1.3, legHeight, 1.3), at(x, legHeight / 2, -25), WOOD, M.Wood).CastShadow = true
		beam(f, "CraneBrace", at(x, 1, -19).Position, at(x, legHeight - 2, -25).Position, 0.8, WOOD_DARK)
		beam(f, "CraneStrut", at(x * 0.4, 1, -27).Position, at(0, 12, -(25 + reach) / 2).Position, 0.7, WOOD_DARK)
	end
	prop(f, "CraneTop", Vector3.new(9, 1.2, 1.4), at(0, legHeight + 0.3, -25), WOOD, M.Wood).CastShadow = true
	beam(f, "CraneX", at(-3.5, 2, -25).Position, at(3.5, legHeight - 1, -25).Position, 0.5, WOOD_DARK)
	beam(f, "CraneX", at(3.5, 2, -25).Position, at(-3.5, legHeight - 1, -25).Position, 0.5, WOOD_DARK)

	-- Pulleys: one on the frame top, one at the arm tip above the rope anchor.
	wheel(f, "Pulley", 2.6, 0.6, at(0, legHeight + 1.6, -25), RUST, M.CorrodedMetal)
	wheel(f, "Pulley", 2.2, 0.6, at(0, 13.6, -reach), RUST, M.CorrodedMetal)
	prop(f, "PulleyCheek", Vector3.new(1.4, 2.6, 0.4), at(0, 13.4, -reach + 0.5), WOOD_DARK, M.Wood)

	-- Big gear and drum beside the winch (DevMap's RopeMount).
	gear(f, 6, at(3.4, 4.2, -21.5))
	wheel(f, "Drum", 2.2, 3.2, at(0, 4.4, -21.5), WOOD_LIGHT, M.Wood)
	rope(f, at(0, 5.4, -21.5).Position, at(0, legHeight + 2.8, -25).Position, 0.3)
	rope(f, at(0, legHeight + 2.8, -25).Position, at(0, 14.6, -reach).Position, 0.3)
end

-- Fence along the pit edge, with a gap at the crane.
local function edgeFence(f: Instance, at: At)
	for _, side in { -1, 1 } do
		for i = 0, 4 do
			local x = side * (6 + i * 4.6)
			solid(f, "FencePost", Vector3.new(0.6, 3.4, 0.6), at(x, 2.7, -25.5), WOOD, M.Wood)
		end
		solid(f, "FenceRail", Vector3.new(19, 0.35, 0.35), at(side * 15.2, 3.6, -25.5), WOOD_LIGHT, M.Wood)
		prop(f, "FenceRail", Vector3.new(19, 0.35, 0.35), at(side * 15.2, 2.2, -25.5), WOOD_LIGHT, M.Wood)
	end
end

-- Camp clutter: rope coils, crates, barrels, a tent behind the base, a campfire.
local function clutter(f: Instance, at: At, index: number)
	ropeCoil(f, at(7, 1, -20), 3.2)
	ropeCoil(f, at(-8, 1, -21), 2.8)
	ropeCoil(f, at(-11, 1.4, 20), 2.6)
	ropeCoil(f, at(11, 1.4, 2), 2.4)
	crate(f, at(-6, 1, -16) * CFrame.Angles(0, 0.3, 0), 2.6)
	crate(f, at(-3.6, 1, -16.6) * CFrame.Angles(0, -0.2, 0), 2)
	crate(f, at(-5, 3.6, -16.2) * CFrame.Angles(0, 0.6, 0), 1.6)
	barrel(f, at(9, 1, -16))
	barrel(f, at(23, 1, 6))

	local tentColor = if index % 2 == 0 then CANVAS else CANVAS:Lerp(Color3.fromRGB(150, 160, 110), 0.5)
	tent(f, at(-15, 1, 32) * CFrame.Angles(0, 0.25, 0), 8, 6, 10, tentColor)
	crate(f, at(-8, 1, 33), 2.4)
	barrel(f, at(-22, 1, 30))

	-- Campfire with a cooking pot in front of the tent.
	local fireBase = at(-6, 1, 30)
	for i = 0, 5 do
		local angle = i / 6 * TAU
		prop(f, "FireStone", Vector3.new(0.9, 0.6, 0.9), fireBase * CFrame.new(math.cos(angle) * 1.6, 0.3, math.sin(angle) * 1.6), STONE, M.Slate)
	end
	local fire = prop(f, "FireLogs", Vector3.new(1.6, 0.6, 1.6), fireBase * CFrame.new(0, 0.4, 0), WOOD_DARK, M.Wood)
	local flame = Instance.new("Fire")
	flame.Size = 3
	flame.Heat = 4
	flame.Parent = fire
end

-- Scaffold tower ------------------------------------------------------------------------

-- A plank walkway from (fromX, fromZ) to (toX, toZ) at deck height y, with side beams, an
-- end post, and a brace back to the tower. Solid, so players can walk out on it.
local function walkway(parent: Instance, at: At, fromX: number, fromZ: number, toX: number, toZ: number, y: number, braceTo: Vector3)
	local a = at(fromX, y - 0.25, fromZ).Position
	local b = at(toX, y - 0.25, toZ).Position
	local length = (b - a).Magnitude
	local frame = CFrame.lookAt((a + b) / 2, b)
	local plank = solid(parent, "Walkway", Vector3.new(WALKWAY_WIDTH, 0.5, length), frame, WOOD_LIGHT, M.WoodPlanks)
	plank.CastShadow = false
	for _, offset in { -WALKWAY_WIDTH / 2, WALKWAY_WIDTH / 2 } do
		prop(parent, "WalkwayBeam", Vector3.new(0.35, 0.45, length), frame * CFrame.new(offset, -0.2, 0), WOOD_DARK, M.Wood)
	end
	prop(parent, "WalkwayRail", Vector3.new(0.25, 0.25, length * 0.8), frame * CFrame.new(WALKWAY_WIDTH / 2, 2.6, length * 0.1), WOOD, M.Wood)
	prop(parent, "WalkwayPost", Vector3.new(0.5, 3, 0.5), CFrame.new(b + Vector3.new(0, 1.5, 0)), WOOD, M.Wood)
	beam(parent, "WalkwayBrace", b - Vector3.new(0, 0.4, 0), braceTo, 0.4, WOOD_DARK)
end

-- A timber scaffold standing on the first ledge below the base, against the cliff, beside
-- (never across) the rope. Three plank decks you can stand on and a climbable truss.
local function scaffold(f: Instance, at: At, index: number, plotRadius: number)
	local side = if index % 2 == 0 then 1 else -1
	local sx = side * 14
	local width, depth = 12, 8
	-- Local z of the pit wall (radius PitRadius) at this sideways offset.
	local wallZ = math.sqrt(H.PitRadius ^ 2 - sx ^ 2) - plotRadius
	local backZ = wallZ + 0.5
	local frontZ = backZ - depth
	local midZ = (backZ + frontZ) / 2
	local bottomY = -H.LedgeDepths[1]
	local topY = -1.5
	local height = topY - bottomY

	local tower = Instance.new("Folder")
	tower.Name = "Scaffold"
	tower.Parent = f

	for _, x in { sx - width / 2, sx + width / 2 } do
		for _, z in { backZ, frontZ } do
			prop(tower, "ScaffoldPost", Vector3.new(0.9, height + 1, 0.9), at(x, bottomY + (height + 1) / 2, z), WOOD, M.Wood).CastShadow = true
		end
	end

	local levels = { bottomY + height / 3, bottomY + height * 2 / 3, topY }
	local previous = bottomY
	for level, y in levels do
		local deckPart = solid(tower, "ScaffoldDeck", Vector3.new(width, 0.5, depth), at(sx, y - 0.25, midZ), WOOD_LIGHT, M.WoodPlanks)
		deckPart.CastShadow = false
		-- A walkway out toward the rope, so players on the scaffold can grab it. It stops
		-- beside the rope line, never under it, so climbers pass freely.
		local reach = plotRadius - H.RopeRadius
		walkway(tower, at, sx - side * 3, frontZ, side * WALKWAY_ROPE_GAP, -reach + 1, y, at(sx - side * (width / 2), y - 6, frontZ).Position)
		-- Edge beams and a rail on the open (pit) side.
		prop(tower, "ScaffoldBeam", Vector3.new(width + 1, 0.6, 0.6), at(sx, y - 0.5, frontZ), WOOD_DARK, M.Wood)
		prop(tower, "ScaffoldBeam", Vector3.new(width + 1, 0.6, 0.6), at(sx, y - 0.5, backZ), WOOD_DARK, M.Wood)
		prop(tower, "ScaffoldRail", Vector3.new(width / 2, 0.3, 0.3), at(sx + side * width / 4, y + 3, frontZ), WOOD, M.Wood) -- the walkway leaves from the other half
		-- X braces on the front and outer side of the section below this deck.
		local x0, x1 = sx - width / 2, sx + width / 2
		beam(tower, "ScaffoldBrace", at(x0, previous, frontZ).Position, at(x1, y, frontZ).Position, 0.45, WOOD_DARK)
		beam(tower, "ScaffoldBrace", at(x1, previous, frontZ).Position, at(x0, y, frontZ).Position, 0.45, WOOD_DARK)
		local outerX = sx + side * width / 2
		beam(tower, "ScaffoldBrace", at(outerX, previous, frontZ).Position, at(outerX, y, backZ).Position, 0.45, WOOD_DARK)
		-- Clutter on the decks.
		if level == 1 then
			crate(tower, at(sx + side * 3, y, midZ + 1), 1.8)
		elseif level == 2 then
			ropeCoil(tower, at(sx - side * 3, y, midZ + 1), 2.2)
		end
		previous = y
	end

	-- A climbable truss up the inner (rope-side) face, from the ledge to the top deck.
	local truss = Instance.new("TrussPart")
	truss.Name = "ScaffoldLadder"
	truss.Anchored = true
	truss.Size = Vector3.new(2, math.floor(height / 2) * 2, 2)
	truss.CFrame = at(sx - side * (width / 2 + 1), bottomY + truss.Size.Y / 2, midZ)
	truss.Color = WOOD
	truss.Material = M.Wood
	truss.Style = Enum.Style.NoSupports
	truss.Parent = tower

	-- A hanging lantern on the top deck and a pulley with rope dangling down the tower.
	lanternPost(tower, at(sx + side * (width / 2 - 1), topY, frontZ + 1), 4, true)
	wheel(tower, "Pulley", 1.6, 0.4, at(sx, topY + 4, frontZ - 0.6), RUST, M.CorrodedMetal)
	prop(tower, "PulleyBeam", Vector3.new(0.6, 0.6, 3), at(sx, topY + 4.5, frontZ + 0.6), WOOD_DARK, M.Wood)
	rope(tower, at(sx, topY + 3.4, frontZ - 0.6).Position, at(sx, bottomY + 6, frontZ - 0.6).Position, 0.2)
end

-- Dresses one base. `at` maps plot-local offsets (studs; -Z faces the pit; Y from rim
-- height) to world CFrames.
function DevBase.dress(map: Instance, at: At, index: number, accent: Color3)
	local f = Instance.new("Model")
	f.Name = "BaseDecor" .. index
	f.Parent = map
	deck(f, at, accent)
	crane(f, at, Config.Plots.Radius - H.RopeRadius)
	edgeFence(f, at)
	clutter(f, at, index)
	scaffold(f, at, index, Config.Plots.Radius)
end

-- Town around the bases ---------------------------------------------------------------

local HOUSE_WALLS = {
	Color3.fromRGB(230, 218, 190),
	Color3.fromRGB(214, 196, 160),
	Color3.fromRGB(236, 226, 204),
	Color3.fromRGB(200, 180, 150),
}
local ROOFS = {
	Color3.fromRGB(176, 72, 52),
	Color3.fromRGB(196, 96, 60),
	Color3.fromRGB(64, 130, 128),
	Color3.fromRGB(86, 130, 80),
	Color3.fromRGB(70, 92, 130),
}

local function townHouse(parent: Instance, base: CFrame, rng: Random, lit: boolean)
	local width = rng:NextNumber(9, 13)
	local depth = rng:NextNumber(8, 11)
	local height = rng:NextNumber(7, 10)
	local wall = HOUSE_WALLS[rng:NextInteger(1, #HOUSE_WALLS)]
	local body = prop(parent, "House", Vector3.new(width, height, depth), base * CFrame.new(0, height / 2, 0), wall, M.Plaster)
	body.CanCollide = true
	body.CastShadow = true
	-- Stone footing and dark timber framing.
	prop(parent, "Footing", Vector3.new(width + 0.4, 1.4, depth + 0.4), base * CFrame.new(0, 0.7, 0), STONE, M.Cobblestone)
	for _, x in { -width / 2, 0, width / 2 } do
		prop(parent, "Timber", Vector3.new(0.5, height, depth + 0.2), base * CFrame.new(x, height / 2, 0), WOOD_DARK, M.Wood)
	end
	prop(parent, "Timber", Vector3.new(width + 0.2, 0.5, depth + 0.2), base * CFrame.new(0, height * 0.55, 0), WOOD_DARK, M.Wood)

	local upper = height
	if rng:NextNumber() < 0.45 then
		-- A second storey that overhangs the first.
		local h2 = rng:NextNumber(5, 7)
		prop(parent, "Upper", Vector3.new(width + 1, h2, depth + 1), base * CFrame.new(0, height + h2 / 2, 0), wall, M.Plaster).CastShadow = true
		prop(parent, "Timber", Vector3.new(width + 1.2, 0.5, depth + 1.2), base * CFrame.new(0, height, 0), WOOD_DARK, M.Wood)
		upper = height + h2
	end
	local roofSize = (depth + 1) / math.sqrt(2) * 1.1
	local roof = prop(parent, "Roof", Vector3.new(width + 2, roofSize, roofSize), base * CFrame.new(0, upper, 0) * CFrame.Angles(math.pi / 4, 0, 0), ROOFS[rng:NextInteger(1, #ROOFS)], M.Slate)
	roof.CastShadow = true
	if rng:NextNumber() < 0.6 then
		prop(parent, "Chimney", Vector3.new(1.4, 5, 1.4), base * CFrame.new(width * 0.3, upper + 2.5, depth * 0.15), STONE, M.Brick)
	end
	local window = prop(parent, "Window", Vector3.new(1.8, 1.8, 0.2), base * CFrame.new(-width * 0.25, height * 0.35, -depth / 2 - 0.1), Color3.fromRGB(255, 210, 140), M.Neon)
	prop(parent, "Window", Vector3.new(1.8, 1.8, 0.2), base * CFrame.new(width * 0.25, height * 0.35, -depth / 2 - 0.1), Color3.fromRGB(255, 210, 140), M.Neon)
	prop(parent, "Door", Vector3.new(2, 3.6, 0.2), base * CFrame.new(0, 1.8 + 0.7, -depth / 2 - 0.1), WOOD_DARK, M.Wood)
	if lit then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 110)
		light.Range = 16
		light.Shadows = false
		light.Parent = window
	end
end

local function windmill(parent: Instance, base: CFrame)
	local height = 22
	local tower = prop(parent, "Windmill", Vector3.new(height, 9, 9), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(220, 208, 182), M.Plaster, Enum.PartType.Cylinder)
	tower.CanCollide = true
	tower.CastShadow = true
	prop(parent, "WindmillBand", Vector3.new(1, 9.4, 9.4), base * CFrame.new(0, 7, 0) * CFrame.Angles(0, 0, math.pi / 2), WOOD_DARK, M.Wood, Enum.PartType.Cylinder)
	local capSize = 9 / math.sqrt(2) * 1.15
	prop(parent, "WindmillCap", Vector3.new(10, capSize, capSize), base * CFrame.new(0, height, 0) * CFrame.Angles(math.pi / 4, 0, 0), ROOFS[1], M.Slate).CastShadow = true
	-- Four sails on a hub facing the pit (local -Z).
	local hub = base * CFrame.new(0, height - 2, -5)
	wheel(parent, "SailHub", 1.6, 1.4, hub * CFrame.Angles(0, math.pi / 2, 0), WOOD_DARK, M.Wood)
	for i = 0, 3 do
		local sail = hub * CFrame.Angles(0, 0, i * math.pi / 2 + 0.4)
		prop(parent, "SailArm", Vector3.new(0.5, 13, 0.4), sail * CFrame.new(0, 6.5, -0.4), WOOD, M.Wood)
		prop(parent, "Sail", Vector3.new(3, 10, 0.15), sail * CFrame.new(1.6, 7.5, -0.5), CANVAS, M.Fabric)
	end
end

local function ruinTower(parent: Instance, base: CFrame, rng: Random)
	local height = rng:NextNumber(16, 26)
	local width = 8
	for _, side in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		-- Each wall breaks off at its own height, so the top looks ruined.
		local h = height * rng:NextNumber(0.6, 1)
		local size = if side[1] == 0 then Vector3.new(width, h, 1.4) else Vector3.new(1.4, h, width)
		local wall = prop(parent, "RuinWall", size, base * CFrame.new(side[1] * width / 2, h / 2, side[2] * width / 2), Color3.fromRGB(160, 156, 146), M.Cobblestone)
		wall.CanCollide = true
		wall.CastShadow = true
		prop(parent, "RuinWindow", Vector3.new(1.5, 2.6, 1.5), base * CFrame.new(side[1] * width / 2, h * 0.6, side[2] * width / 2), Color3.fromRGB(40, 38, 36), M.Slate)
	end
	for _ = 1, 4 do
		local offset = Vector3.new(rng:NextNumber(-7, 7), 0.6, rng:NextNumber(-7, 7))
		prop(parent, "Rubble", Vector3.new(rng:NextNumber(1, 2.4), rng:NextNumber(0.8, 1.6), rng:NextNumber(1, 2.4)), base * CFrame.new(offset) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 3), 0), STONE, M.Cobblestone)
	end
	-- Ivy down one face.
	prop(parent, "Ivy", Vector3.new(4, height * 0.5, 0.5), base * CFrame.new(-1, height * 0.3, -width / 2 - 0.5), Color3.fromRGB(70, 120, 60), M.Grass)
end

local function tree(parent: Instance, base: CFrame, rng: Random)
	local height = rng:NextNumber(10, 16)
	local trunk = prop(parent, "Trunk", Vector3.new(height, 1.6, 1.6), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), WOOD, M.Wood, Enum.PartType.Cylinder)
	trunk.CastShadow = true
	local leaf = Color3.fromRGB(70, 128, 58):Lerp(Color3.fromRGB(120, 150, 60), rng:NextNumber(0, 0.6))
	local canopy = rng:NextNumber(8, 11)
	prop(parent, "Canopy", Vector3.new(canopy, canopy, canopy), base * CFrame.new(0, height, 0), leaf, M.Grass, Enum.PartType.Ball).CastShadow = true
	prop(parent, "Canopy", Vector3.new(canopy * 0.7, canopy * 0.7, canopy * 0.7), base * CFrame.new(canopy * 0.35, height - 1.5, 0.5), leaf:Lerp(Color3.new(0, 0, 0), 0.08), M.Grass, Enum.PartType.Ball)
end

-- Town and scenery around the bases. `center` is the pit centre at rim height.
function DevBase.buildTown(map: Instance, center: Vector3)
	local rng = Random.new(2024)
	local town = Instance.new("Model")
	town.Name = "TownDecor"
	town.Parent = map

	local function around(radius: number, angle: number): CFrame
		local position = Vector3.new(center.X + math.cos(angle) * radius, center.Y, center.Z + math.sin(angle) * radius)
		return CFrame.lookAt(position, Vector3.new(center.X, center.Y, center.Z)) -- local -Z faces the pit
	end

	local step = TAU / Config.Plots.Count
	for i = 0, Config.Plots.Count - 1 do
		local plotAngle = i * step
		local gap = plotAngle + step / 2

		-- Behind the road: a row of houses, staggered in two rings.
		for k = -2, 2 do
			local angle = plotAngle + k * step / 5 + rng:NextNumber(-0.02, 0.02)
			local radius = if k % 2 == 0 then 218 else 232
			townHouse(town, around(radius, angle) * CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0), rng, k == 0)
		end

		-- Between bases: trees, a camp tent, and a lamp on the lip.
		tree(town, around(rng:NextNumber(150, 175), gap + rng:NextNumber(-0.08, 0.08)), rng)
		tree(town, around(rng:NextNumber(178, 186), gap + rng:NextNumber(-0.12, 0.12)), rng)
		if i % 2 == 0 then
			tent(town, around(160, gap + 0.06) * CFrame.Angles(0, 0.7, 0), 7, 5, 8, CANVAS)
			crate(town, around(156, gap - 0.04), 2.2)
		else
			ropeCoil(town, around(150, gap), 3)
			barrel(town, around(154, gap + 0.05))
		end

		if i % 2 == 0 then
			windmill(town, around(238, gap))
		else
			ruinTower(town, around(206, gap), rng)
		end
	end
end

return DevBase
