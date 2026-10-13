--[[
	Builds the grappling hook (Config.Grapple) from parts: a wooden launcher grip, a
	coil of rope, and a three-pronged iron hook at the front.

	Shared: the server makes the tool from it, the client the Forge preview. Same layout
	as PickaxeModels (shaft along the Handle's local Z, front at +Z, grip at -Z), so it
	uses PickaxeModels.Grip.
]]

local GrappleModel = {}

local M = Enum.Material
local WOOD = Color3.fromRGB(110, 76, 48)
local IRON = Color3.fromRGB(96, 96, 104)
local ROPE = Color3.fromRGB(196, 160, 106)

-- forTool: unanchored, massless, welded to the Handle. Otherwise anchored.
function GrappleModel.build(forTool: boolean): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Grapple"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 0.4, 3.2)
	handle.Color = WOOD
	handle.Material = M.Wood
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
	local along = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis along Z

	add(cyl, Vector3.new(1.1, 0.5, 0.5), CFrame.new(0, 0, -1.4) * along, Color3.fromRGB(70, 44, 28), M.Leather)
	-- Rope coil around the middle, with brass bands.
	add(cyl, Vector3.new(1.2, 1.1, 1.1), CFrame.new(0, 0, 0.1) * along, ROPE, M.Fabric)
	for _, z in { -0.55, 0.75 } do
		add(cyl, Vector3.new(0.12, 1.2, 1.2), CFrame.new(0, 0, z) * along, Color3.fromRGB(176, 136, 72), M.Metal)
	end
	-- The hook: a shank and three curved prongs.
	add(block, Vector3.new(0.22, 0.22, 1.1), CFrame.new(0, 0, 2), IRON, M.Metal)
	for i = 0, 2 do
		local spin = CFrame.Angles(0, 0, i / 3 * 2 * math.pi)
		add(block, Vector3.new(0.16, 0.7, 0.16), CFrame.new(0, 0, 2.5) * spin * CFrame.new(0, 0.32, 0) * CFrame.Angles(-0.5, 0, 0), IRON, M.Metal)
		add(block, Vector3.new(0.14, 0.14, 0.45), CFrame.new(0, 0, 2.5) * spin * CFrame.new(0, 0.66, -0.12), IRON, M.Metal)
	end
	add(ball, Vector3.new(0.32, 0.32, 0.32), CFrame.new(0, 0, 2.55), IRON, M.Metal)
	return model, handle
end

return GrappleModel
