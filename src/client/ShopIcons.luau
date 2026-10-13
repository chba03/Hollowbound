--[[
	Little 3D items for menu cards and tabs, built from parts inside a ViewportFrame:
	coins, a coin purse, a treasure chest, a rope coil, a lantern, a clockwork gear, and
	a relic crate. No uploaded images. Presentation only.
]]

local ShopIcons = {}

local M = Enum.Material

local GOLD = Color3.fromRGB(240, 190, 70)
local GOLD_DARK = Color3.fromRGB(190, 130, 40)
local WOOD = Color3.fromRGB(120, 78, 46)
local WOOD_DARK = Color3.fromRGB(80, 50, 30)
local BRASS = Color3.fromRGB(200, 155, 70)
local ROPE = Color3.fromRGB(200, 162, 104)
local LEATHER = Color3.fromRGB(130, 80, 48)

local function add(model: Model, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local UP = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis pointing up

local BUILDERS = {}

function BUILDERS.coins(m: Model)
	local stacks = { { -0.9, 0, 0.2, 6 }, { 0.5, 0, -0.3, 9 }, { 1.1, 0, 0.8, 4 }, { -0.2, 0, 1.0, 3 } }
	for _, stack in stacks do
		for i = 0, stack[4] - 1 do
			add(m, Enum.PartType.Cylinder, Vector3.new(0.22, 1.1, 1.1), CFrame.new(stack[1] + (i % 2) * 0.04, i * 0.23, stack[3]) * UP, if i % 3 == 0 then GOLD_DARK else GOLD, M.Foil)
		end
	end
	add(m, Enum.PartType.Cylinder, Vector3.new(0.22, 1.1, 1.1), CFrame.new(-1.3, 0.25, 1.2) * CFrame.Angles(0.3, 0, 1.2), GOLD, M.Foil)
end

function BUILDERS.purse(m: Model)
	add(m, Enum.PartType.Ball, Vector3.new(2.6, 2.6, 2.6), CFrame.new(0, 1.2, 0), LEATHER, M.Leather)
	add(m, Enum.PartType.Cylinder, Vector3.new(0.7, 1.1, 1.1), CFrame.new(0, 2.6, 0) * UP, LEATHER:Lerp(Color3.new(0, 0, 0), 0.15), M.Leather)
	add(m, Enum.PartType.Cylinder, Vector3.new(0.25, 1.25, 1.25), CFrame.new(0, 2.4, 0) * UP, ROPE, M.Fabric)
	for i = 0, 4 do
		add(m, Enum.PartType.Cylinder, Vector3.new(0.2, 0.9, 0.9), CFrame.new(-1.2 + i * 0.5, 0.1 + (i % 2) * 0.25, 1.2) * CFrame.Angles(0.2, 0, 1.4), GOLD, M.Foil)
	end
end

function BUILDERS.chest(m: Model)
	add(m, Enum.PartType.Block, Vector3.new(3, 1.6, 2), CFrame.new(0, 0.8, 0), WOOD, M.WoodPlanks)
	add(m, Enum.PartType.Cylinder, Vector3.new(3, 2, 2), CFrame.new(0, 1.6, 0), WOOD, M.WoodPlanks)
	for _, x in { -1.1, 1.1 } do
		add(m, Enum.PartType.Block, Vector3.new(0.25, 1.7, 2.1), CFrame.new(x, 0.8, 0), BRASS, M.Metal)
		add(m, Enum.PartType.Cylinder, Vector3.new(0.25, 2.1, 2.1), CFrame.new(x, 1.6, 0), BRASS, M.Metal)
	end
	add(m, Enum.PartType.Block, Vector3.new(0.5, 0.6, 0.2), CFrame.new(0, 1.4, -1.05), BRASS, M.Metal)
	for i = 0, 5 do
		add(m, Enum.PartType.Cylinder, Vector3.new(0.2, 0.7, 0.7), CFrame.new(-1 + i * 0.4, 2.6 + (i % 2) * 0.1, -0.2) * CFrame.Angles(0.4, 0, 1.3), GOLD, M.Foil)
	end
end

function BUILDERS.rope(m: Model)
	for i = 0, 3 do
		local d = 3 - i * 0.35
		add(m, Enum.PartType.Cylinder, Vector3.new(0.5, d, d), CFrame.new(0.05 * i, 0.25 + i * 0.42, 0) * UP, if i % 2 == 0 then ROPE else ROPE:Lerp(WOOD, 0.2), M.Fabric)
	end
	add(m, Enum.PartType.Cylinder, Vector3.new(1.9, 1.1, 1.1), CFrame.new(0, 0.9, 0) * UP, Color3.fromRGB(60, 44, 30), M.Fabric)
	add(m, Enum.PartType.Cylinder, Vector3.new(2.2, 0.4, 0.4), CFrame.new(1.4, 0.7, 0.4) * CFrame.Angles(0, 0.3, 0.2), ROPE, M.Fabric)
end

function BUILDERS.lantern(m: Model)
	add(m, Enum.PartType.Block, Vector3.new(1.8, 0.3, 1.8), CFrame.new(0, 0.15, 0), BRASS, M.Metal)
	add(m, Enum.PartType.Block, Vector3.new(1.8, 0.3, 1.8), CFrame.new(0, 2.6, 0), BRASS, M.Metal)
	add(m, Enum.PartType.Block, Vector3.new(1.3, 2.1, 1.3), CFrame.new(0, 1.4, 0), Color3.fromRGB(255, 196, 90), M.Neon)
	for _, x in { -0.8, 0.8 } do
		for _, z in { -0.8, 0.8 } do
			add(m, Enum.PartType.Block, Vector3.new(0.18, 2.3, 0.18), CFrame.new(x, 1.4, z), BRASS, M.Metal)
		end
	end
	add(m, Enum.PartType.Cylinder, Vector3.new(0.18, 1.1, 1.1), CFrame.new(0, 3.2, 0), BRASS, M.Metal)
end

function BUILDERS.gear(m: Model)
	local face = CFrame.Angles(0, math.pi / 2, 0) -- disc facing the camera
	add(m, Enum.PartType.Cylinder, Vector3.new(0.5, 2.6, 2.6), CFrame.new(0, 1.6, 0) * face, BRASS, M.Metal)
	add(m, Enum.PartType.Cylinder, Vector3.new(0.7, 0.8, 0.8), CFrame.new(0, 1.6, 0) * face, Color3.fromRGB(70, 50, 30), M.Metal)
	for i = 0, 9 do
		local angle = i / 10 * 2 * math.pi
		add(m, Enum.PartType.Block, Vector3.new(0.45, 0.6, 0.5), CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, angle) * CFrame.new(0, 1.45, 0), BRASS, M.Metal)
	end
	add(m, Enum.PartType.Cylinder, Vector3.new(0.4, 1.5, 1.5), CFrame.new(1.4, 0.6, 0.4) * face, Color3.fromRGB(176, 104, 58), M.Metal)
end

function BUILDERS.crate(m: Model)
	add(m, Enum.PartType.Block, Vector3.new(2.4, 2.4, 2.4), CFrame.new(0, 1.2, 0), WOOD_DARK, M.WoodPlanks)
	for _, y in { 0.25, 2.15 } do
		add(m, Enum.PartType.Block, Vector3.new(2.5, 0.3, 2.5), CFrame.new(0, y, 0), BRASS, M.Metal)
	end
	add(m, Enum.PartType.Ball, Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, 2.7, 0), Color3.fromRGB(170, 100, 255), M.Neon)
	add(m, Enum.PartType.Block, Vector3.new(0.7, 0.7, 0.2), CFrame.new(0, 1.2, -1.25) * CFrame.Angles(0, 0, math.pi / 4), Color3.fromRGB(170, 100, 255), M.Neon)
end

-- A ViewportFrame showing `model`, framed from `direction` (default: front, above).
function ShopIcons.fromModel(parent: Instance, model: Model, size: UDim2, position: UDim2, z: number?, direction: Vector3?): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Icon"
	viewport.BackgroundTransparency = 1
	viewport.Size = size
	viewport.Position = position
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Ambient = Color3.fromRGB(150, 130, 110)
	viewport.LightColor = Color3.fromRGB(255, 236, 200)
	viewport.LightDirection = Vector3.new(-1, -1.5, -0.6)
	viewport.ZIndex = z or 3
	viewport.Parent = parent
	model.Parent = viewport
	local cframe, extent = model:GetBoundingBox()
	local radius = extent.Magnitude / 2
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	local look = (direction or Vector3.new(0.45, 0.5, -1)).Unit
	camera.CFrame = CFrame.lookAt(cframe.Position + look * distance, cframe.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

-- Fills `parent` with a ViewportFrame showing the `kind` item. Returns the frame.
function ShopIcons.make(parent: Instance, kind: string, size: UDim2, position: UDim2, z: number?): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Icon"
	viewport.BackgroundTransparency = 1
	viewport.Size = size
	viewport.Position = position
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Ambient = Color3.fromRGB(150, 130, 110)
	viewport.LightColor = Color3.fromRGB(255, 236, 200)
	viewport.LightDirection = Vector3.new(-1, -1.5, -0.6)
	viewport.ZIndex = z or 3
	viewport.Parent = parent

	local model = Instance.new("Model")
	;(BUILDERS[kind] or BUILDERS.coins)(model)
	model.Parent = viewport

	-- Frame the model from the front, a little above.
	local cframe, extent = model:GetBoundingBox()
	local radius = extent.Magnitude / 2
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	local direction = Vector3.new(0.45, 0.5, -1).Unit
	camera.CFrame = CFrame.lookAt(cframe.Position + direction * distance, cframe.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

return ShopIcons
