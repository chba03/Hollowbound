--[[
	Local atmosphere for each Hollow layer. Presentation only: it reads the HB_Layer
	attribute the server sets and tweens this client's Atmosphere and a colour
	correction, and drifts the layer's ambient motes around the camera. Lighting changes
	made on a client are never replicated, so each player sees the mood of their own depth.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))

local LayerEffects = {}

local TWEEN = TweenInfo.new(1.5, Enum.EasingStyle.Sine)

function LayerEffects.start(hud)
	local player = Players.LocalPlayer

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0
		atmosphere.Parent = Lighting
	end
	local surface = {
		Density = atmosphere.Density,
		Color = atmosphere.Color,
		Decay = atmosphere.Decay,
		Haze = atmosphere.Haze,
	}

	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "HB_LayerTint"
	correction.Parent = Lighting

	-- One emitter for the whole client: a box that follows the camera and drifts this
	-- layer's motes (pollen, spray, ice, dust, spores) through the air around you.
	local motesBox = Instance.new("Part")
	motesBox.Name = "HB_Motes"
	motesBox.Anchored = true
	motesBox.CanCollide = false
	motesBox.CanQuery = false
	motesBox.CanTouch = false
	motesBox.Transparency = 1
	motesBox.Size = Vector3.new(70, 40, 70)
	motesBox.Parent = workspace.CurrentCamera

	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.Lifetime = NumberRange.new(5, 9)
	motes.Rotation = NumberRange.new(0, 360)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	motes.Rate = 0
	motes.Parent = motesBox

	RunService.RenderStepped:Connect(function()
		if motes.Rate > 0 then
			motesBox.CFrame = CFrame.new(workspace.CurrentCamera.CFrame.Position)
		end
	end)

	local current = -1
	local function apply()
		local layer = player:GetAttribute("HB_Layer") or 0
		if layer == current then
			return
		end
		local previous = current
		current = layer

		local def = Config.Layers[layer]
		if def then
			TweenService:Create(atmosphere, TWEEN, {
				Density = def.density,
				Color = def.fog,
				Decay = def.fog:Lerp(Color3.new(0, 0, 0), 0.5),
				Haze = 2,
			}):Play()
			TweenService:Create(correction, TWEEN, { TintColor = def.tint, Brightness = def.brightness }):Play()
			local m = def.motes
			motes.Color = ColorSequence.new(m.color)
			motes.Size = NumberSequence.new(m.size)
			motes.Speed = NumberRange.new(m.speed * 0.5, m.speed)
			motes.LightEmission = m.glow
			motes.Rate = m.rate
			if previous >= 0 then
				hud:banner(`Layer {layer}`, def.name)
			end
		else
			TweenService:Create(atmosphere, TWEEN, surface):Play()
			TweenService:Create(correction, TWEEN, { TintColor = Color3.new(1, 1, 1), Brightness = 0 }):Play()
			motes.Rate = 0
		end
	end

	player:GetAttributeChangedSignal("HB_Layer"):Connect(apply)
	apply()
end

return LayerEffects
