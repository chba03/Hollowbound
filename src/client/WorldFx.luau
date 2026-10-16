--[[
	Local-only world presentation (milestone 5). Changes nothing on the server.

	- Camera: sets Config.Camera.FieldOfView once. Zoom stays player-controlled (the server
	  sets the zoom limits); no cinematic moves.
	- Depth atmosphere: blends the installed preset's HB_Atmosphere and HB_ColorCorrection
	  toward the preset's DepthBlend as the player descends (HB_Depth attribute). Only
	  objects named HB_* are touched; other Lighting effects are left alone. If the preset
	  is not installed, nothing happens.
	- Relic idle: pieces named HB_Float inside world relic models spin, bob, or orbit.
	  Works with streaming: relics that stream out are forgotten, and re-read when they
	  stream back in.
	- Landings: a hard landing makes a small dust burst and a brief camera dip.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))

local WorldFx = {}

local player = Players.LocalPlayer

local function rgb(c): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Depth atmosphere ----------------------------------------------------------------------------

local preset = Config.World.LightingPresets[Config.World.LightingPreset]
local currentBlend = -1

local function applyDepth()
	local atmosphere = Lighting:FindFirstChild("HB_Atmosphere")
	local correction = Lighting:FindFirstChild("HB_ColorCorrection")
	if not preset or not preset.DepthBlend or not atmosphere then
		return
	end
	local meters = player:GetAttribute("HB_Depth")
	local studs = if typeof(meters) == "number" then meters / Config.World.MetersPerStud else 0
	local t = math.clamp(studs / Config.World.FloorDepth, 0, 1)
	t = math.floor(t * 20 + 0.5) / 20 -- small steps, so tweens stay rare
	if t == currentBlend then
		return
	end
	currentBlend = t
	local info = TweenInfo.new(2)
	local base, deep = preset.Atmosphere, preset.DepthBlend
	if atmosphere:IsA("Atmosphere") then
		TweenService:Create(atmosphere, info, {
			Density = base.Density + (deep.Density - base.Density) * t,
			Color = rgb(base.Color):Lerp(rgb(deep.Color), t),
		}):Play()
	end
	if correction and correction:IsA("ColorCorrectionEffect") then
		TweenService:Create(correction, info, { TintColor = rgb(preset.ColorCorrection.TintColor):Lerp(rgb(deep.TintColor), t) }):Play()
	end
end

-- Relic idle ------------------------------------------------------------------------------------

local bases: { [BasePart]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function animateRelics(now: number)
	for _, core in CollectionService:GetTagged(Config.Tags.WorldRelic) do
		local model = core.Parent
		if not (model and model:IsA("Model")) then
			continue
		end
		for _, piece in model:GetChildren() do
			if piece.Name ~= "HB_Float" or not piece:IsA("BasePart") then
				continue
			end
			local base = bases[piece]
			if not base then
				base = piece.CFrame
				bases[piece] = base
			end
			local bob = math.sin(now * 1.6 + (piece:GetAttribute("FloatPhase") or 0)) * 0.15
			local orbit = piece:GetAttribute("FloatOrbit")
			if orbit then
				local phase = (piece:GetAttribute("FloatPhase") or 0) + now * 0.8
				local center = core.Position + Vector3.new(0, base.Position.Y - core.Position.Y, 0)
				piece.CFrame = CFrame.new(center + Vector3.new(math.cos(phase) * orbit, bob, math.sin(phase) * orbit)) * CFrame.Angles(0, -phase, 0)
			else
				local spin = math.rad((piece:GetAttribute("FloatSpin") or 30) * now)
				piece.CFrame = CFrame.new(base.Position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, spin, 0) * (base - base.Position)
			end
		end
	end
end

-- Landings --------------------------------------------------------------------------------------

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		return
	end
	local fastest = 0
	local connection = RunService.Heartbeat:Connect(function()
		if humanoid:GetState() == Enum.HumanoidStateType.Freefall then
			fastest = math.max(fastest, -root.AssemblyLinearVelocity.Y)
		end
	end)
	humanoid.StateChanged:Connect(function(_, new)
		if new ~= Enum.HumanoidStateType.Landed then
			return
		end
		local speed = fastest
		fastest = 0
		if speed < 45 then
			return
		end
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, -humanoid.HipHeight - root.Size.Y / 2, 0)
		attachment.Parent = root
		local dust = Instance.new("ParticleEmitter")
		dust.Color = ColorSequence.new(Color3.fromRGB(190, 180, 160))
		dust.Size = NumberSequence.new(0.8, 2.4)
		dust.Transparency = NumberSequence.new(0.4, 1)
		dust.Lifetime = NumberRange.new(0.4, 0.7)
		dust.Speed = NumberRange.new(6, 10)
		dust.SpreadAngle = Vector2.new(80, 10)
		dust.EmissionDirection = Enum.NormalId.Top
		dust.Rate = 0
		dust.Parent = attachment
		dust:Emit(math.clamp(math.floor(speed / 6), 6, 24))
		task.delay(1, function()
			attachment:Destroy()
		end)
		local dip = math.clamp(speed / 160, 0.2, 0.8)
		local down = TweenService:Create(humanoid, TweenInfo.new(0.08), { CameraOffset = Vector3.new(0, -dip, 0) })
		down.Completed:Connect(function()
			TweenService:Create(humanoid, TweenInfo.new(0.25), { CameraOffset = Vector3.zero }):Play()
		end)
		down:Play()
	end)
	character.AncestryChanged:Connect(function()
		if not character.Parent then
			connection:Disconnect()
		end
	end)
end

function WorldFx.start()
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = Config.Camera.FieldOfView
	end
	player:GetAttributeChangedSignal("HB_Depth"):Connect(applyDepth)
	applyDepth()
	RunService.RenderStepped:Connect(function()
		animateRelics(os.clock())
	end)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
end

return WorldFx
