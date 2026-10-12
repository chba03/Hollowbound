--[[
	A cloud layer in the Hollow below what your rope can nearly reach. Presentation only,
	on this client: each player sees their own veil, set by their own rope.

	Your rope reaches some layer L (Progression.layerForDepth of HB_RopeLength). Layers
	more than Config.Veil.LayersAhead below L are veiled: from the top of layer
	L + LayersAhead + 1 down, drifting fog clouds and a few faint sheets thicken with
	depth, so what lies below shows only dimly, as through mist, not behind a wall. A
	longer rope moves the veil deeper; when it would sit below the last layer, it goes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))

local DepthVeil = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local MOVE = TweenInfo.new(2, Enum.EasingStyle.Sine)

local function part(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Parent = parent
	return p
end

function DepthVeil.start()
	local player = Players.LocalPlayer
	local cfg = Config.Veil
	local center = workspace:GetAttribute("HB_HollowCenter")
	while typeof(center) ~= "Vector3" do
		workspace:GetAttributeChangedSignal("HB_HollowCenter"):Wait()
		center = workspace:GetAttribute("HB_HollowCenter")
	end

	local model = Instance.new("Model")
	model.Name = "HB_DepthVeil"
	model.Parent = workspace

	-- Faint sheets, one under another, that add up to a thick haze further down.
	local sheets = {}
	for i = 1, cfg.Sheets do
		local sheet = part("VeilSheet", Vector3.new(0.2, 1, 1), CFrame.new(), model)
		sheet.Shape = Enum.PartType.Cylinder
		sheet.Material = Enum.Material.SmoothPlastic
		sheet.Transparency = 1
		sheets[i] = sheet
	end

	-- Drifting clouds on and just above the sheets.
	local cloudBox = part("VeilClouds", Vector3.new(1, cfg.CloudThickness, 1), CFrame.new(), model)
	cloudBox.Transparency = 1
	local clouds = Instance.new("ParticleEmitter")
	clouds.Texture = SMOKE
	clouds.Shape = Enum.ParticleEmitterShape.Box
	clouds.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	clouds.Lifetime = NumberRange.new(14, 22)
	clouds.Rate = 0
	clouds.Speed = NumberRange.new(0.5, 2)
	clouds.SpreadAngle = Vector2.new(180, 15)
	clouds.Rotation = NumberRange.new(0, 360)
	clouds.RotSpeed = NumberRange.new(-4, 4)
	clouds.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 30),
		NumberSequenceKeypoint.new(1, 60),
	})
	clouds.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.55),
		NumberSequenceKeypoint.new(0.75, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	clouds.LightInfluence = 1
	clouds.Parent = cloudBox

	local function place()
		local length = player:GetAttribute("HB_RopeLength")
		local reach = Progression.layerForDepth(if typeof(length) == "number" then length else 0)
		local veilLayer = math.max(reach, 1) + cfg.LayersAhead + 1
		if veilLayer > #Config.Layers then
			clouds.Rate = 0
			for _, sheet in sheets do
				TweenService:Create(sheet, MOVE, { Transparency = 1 }):Play()
			end
			return
		end

		local depth = (veilLayer - 1) * Config.Hollow.LayerHeight
		local color = Config.Layers[veilLayer].fog:Lerp(Color3.new(1, 1, 1), 0.35)
		for i, sheet in sheets do
			local d = depth + (i - 1) * cfg.SheetGap
			local radius = Progression.pitRadiusAt(d) + 2
			sheet.Color = color
			sheet.Size = Vector3.new(0.2, radius * 2, radius * 2)
			local goal = CFrame.new(center - Vector3.new(0, d, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			TweenService:Create(sheet, MOVE, { CFrame = goal, Transparency = cfg.SheetTransparency }):Play()
		end

		local radius = Progression.pitRadiusAt(depth)
		cloudBox.Size = Vector3.new(radius * 1.6, cfg.CloudThickness, radius * 1.6)
		TweenService:Create(cloudBox, MOVE, { CFrame = CFrame.new(center - Vector3.new(0, depth - cfg.CloudThickness / 2 + 4, 0)) }):Play()
		clouds.Color = ColorSequence.new(color)
		clouds.Rate = cfg.CloudRate
	end

	player:GetAttributeChangedSignal("HB_RopeLength"):Connect(place)
	place()
end

return DepthVeil
