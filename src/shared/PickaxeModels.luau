--[[
	Builds a pickaxe (Config.Pickaxes) from parts: a shaft with a leather grip and a
	two-pointed head curving toward the hand, plus details for its layer's style:

	  vine     green vines wound up the shaft          (Mistfall Gardens)
	  wood     a dark wooden head bound with rope       (The Hanging Wood)
	  stone    a slate head with a blue gem             (Veilfall Cliffs)
	  crystal  an ice head with crystal shards          (Glasswood Hollows)
	  tide     a corroded teal head with a pearl         (Drowned Terraces)
	  gear     a brass head around a turning gear        (Rootbound Ruins)
	  bone     an ivory head, a glowing core, spine knobs (The Marrow)
	  ember    a basalt head with glowing cracks, a hot core (Emberdeep Forges)
	  shroom   a violet glass head with a mushroom cap      (Gloamcap Grotto)
	  lumen    a gilded head, a halo, a radiant core        (The Lumen Core)

	Shared: the server makes the tool from it, the client the Forge previews.
	Layout: the shaft runs along the Handle's local Z, the head at +Z, the grip at -Z
	(the classic tool grip, see Grip below).
]]

local PickaxeModels = {}

local M = Enum.Material
local LEATHER = Color3.fromRGB(70, 44, 28)

-- Tool grip: the hand holds the handle low on the shaft, head up and forward.
PickaxeModels.Grip = {
	Pos = Vector3.new(0, 0, -1.4),
	Forward = Vector3.new(-1, 0, 0),
	Right = Vector3.new(0, 1, 0),
	Up = Vector3.new(0, 0, 1),
}

-- Builds the pickaxe. forTool: unanchored, massless, welded to the Handle, so it can be
-- held. Otherwise anchored (for a ViewportFrame or a display). Returns the model and
-- its Handle part.
function PickaxeModels.build(def, forTool: boolean): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = def.id

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.32, 0.32, 4.2)
	handle.Color = def.shaft
	handle.Material = def.shaftMaterial
	handle.CanCollide = false
	handle.CastShadow = false
	handle.Anchored = not forTool
	handle.Parent = model
	model.PrimaryPart = handle

	local function add(shape: Enum.PartType, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): BasePart
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.CFrame = handle.CFrame * offset
		p.Color = color
		p.Material = material
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if forTool then
			p.Anchored = false
			p.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = p
			weld.Parent = p
		else
			p.Anchored = true
		end
		p.Parent = model
		return p
	end
	local block, ball, cyl = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder
	local along = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis along the shaft (Z)

	-- Grip, pommel, and the head: a centre block with two curved points.
	add(cyl, Vector3.new(1.1, 0.42, 0.42), CFrame.new(0, 0, -1.4) * along, LEATHER, M.Leather)
	add(ball, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0, -2.15), def.head, def.headMaterial)
	local head, headMat = def.head, def.headMaterial
	add(block, Vector3.new(0.8, 0.62, 0.8), CFrame.new(0, 0, 1.95), head, headMat)
	for _, side in { 1, -1 } do
		local tilt = math.rad(14) * side
		add(block, Vector3.new(1.4, 0.44, 0.52), CFrame.new(1.05 * side, 0, 1.82) * CFrame.Angles(0, tilt, 0), head, headMat)
		add(block, Vector3.new(0.7, 0.32, 0.36), CFrame.new(1.95 * side, 0, 1.5) * CFrame.Angles(0, tilt * 2.4, 0), head, headMat)
	end

	local style = def.style
	if style == "vine" then
		for i = 0, 5 do
			add(cyl, Vector3.new(0.14, 0.42, 0.42), CFrame.new(0, 0, -0.7 + i * 0.42) * along * CFrame.Angles(0, 0, i * 0.5), Color3.fromRGB(70, 140, 60), M.Grass)
		end
		add(ball, Vector3.new(0.35, 0.35, 0.35), CFrame.new(0.22, 0, 0.9), Color3.fromRGB(240, 240, 220), M.SmoothPlastic)
	elseif style == "wood" then
		for _, z in { 1.62, 2.28 } do
			add(cyl, Vector3.new(0.12, 0.95, 0.95), CFrame.new(0, 0, z) * along, Color3.fromRGB(196, 160, 106), M.Fabric)
		end
	elseif style == "stone" then
		add(ball, Vector3.new(0.42, 0.42, 0.42), CFrame.new(0, 0.32, 1.95), def.accent, M.Neon)
	elseif style == "crystal" then
		for i, offset in { Vector3.new(0.3, 0, 2.5), Vector3.new(-0.25, 0.1, 2.45), Vector3.new(0, -0.2, 2.6) } do
			add(block, Vector3.new(0.22, 0.22, 0.8), CFrame.new(offset) * CFrame.Angles(0.3 * i, 0.4 * i, 0), def.accent, M.Glass)
		end
		add(ball, Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, 0.3, 1.95), def.accent, M.Neon)
	elseif style == "tide" then
		add(ball, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0.34, 1.95), def.accent, M.Glass)
		add(cyl, Vector3.new(0.16, 0.5, 0.5), CFrame.new(0, 0, 1.5) * along, Color3.fromRGB(196, 180, 120), M.Metal)
	elseif style == "gear" then
		local face = CFrame.Angles(0, 0, math.pi / 2) -- disc facing up (Y)
		add(cyl, Vector3.new(0.2, 1.05, 1.05), CFrame.new(0, 0.34, 1.95) * face, def.head:Lerp(Color3.new(0, 0, 0), 0.2), M.Metal)
		for i = 0, 7 do
			local angle = i / 8 * 2 * math.pi
			add(block, Vector3.new(0.2, 0.18, 0.18), CFrame.new(0, 0.34, 1.95) * CFrame.Angles(0, angle, 0) * CFrame.new(0.58, 0, 0), def.head, M.Metal)
		end
		add(ball, Vector3.new(0.26, 0.26, 0.26), CFrame.new(0, 0.46, 1.95), def.accent, M.Neon)
	elseif style == "bone" then
		for i = 0, 3 do
			add(ball, Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, 0, -0.6 + i * 0.55), def.head, M.Marble)
		end
		add(ball, Vector3.new(0.48, 0.48, 0.48), CFrame.new(0, 0.32, 1.95), def.accent, M.Neon)
	elseif style == "ember" then
		-- Glowing cracks along the head, and a hot core.
		for _, side in { 1, -1 } do
			add(block, Vector3.new(1.3, 0.08, 0.12), CFrame.new(1.05 * side, 0.23, 1.82) * CFrame.Angles(0, math.rad(14) * side, 0), def.accent, M.Neon)
		end
		add(ball, Vector3.new(0.46, 0.46, 0.46), CFrame.new(0, 0.32, 1.95), def.accent, M.Neon)
		for _, z in { 1.45, 2.4 } do
			add(cyl, Vector3.new(0.14, 0.9, 0.9), CFrame.new(0, 0, z) * along, Color3.fromRGB(150, 110, 60), M.CorrodedMetal)
		end
	elseif style == "shroom" then
		local face = CFrame.Angles(0, 0, math.pi / 2)
		add(ball, Vector3.new(0.9, 0.36, 0.9), CFrame.new(0, 0.42, 1.95), Color3.fromRGB(95, 60, 140), M.SmoothPlastic)
		add(cyl, Vector3.new(0.08, 0.8, 0.8), CFrame.new(0, 0.34, 1.95) * face, def.accent, M.Neon)
		for i = 0, 2 do
			add(ball, Vector3.new(0.14, 0.14, 0.14), CFrame.new(0.2 - i * 0.2, 0.58, 1.85 + i * 0.1), def.accent, M.Neon)
		end
	elseif style == "lumen" then
		for i = 0, 7 do
			local angle = i / 8 * 2 * math.pi
			add(block, Vector3.new(0.16, 0.1, 0.3), CFrame.new(0, 0.62, 1.95) * CFrame.Angles(0, angle, 0) * CFrame.new(0.5, 0, 0), def.accent, M.Neon)
		end
		add(cyl, Vector3.new(0.12, 0.5, 0.5), CFrame.new(0, 0, 1.45) * along, def.accent, M.Foil)
		add(ball, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0.32, 1.95), Color3.fromRGB(255, 250, 230), M.Neon)
	end

	if def.accent then
		local glow = Instance.new("PointLight")
		glow.Color = def.accent
		glow.Range = 6
		glow.Brightness = 0.8
		glow.Shadows = false
		glow.Parent = handle
	end
	return model, handle
end

return PickaxeModels
