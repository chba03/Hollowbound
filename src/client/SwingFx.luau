--[[
	Plays the pickaxe swing (shared SwingAnimation) on every player who swings, when
	the server accepts a swing (HB_SwingAt changes). The pose is set on the joints
	directly each frame (R15 and R6), so it works on live servers too: animations
	registered at runtime only play in Studio. Every client does this for everyone it
	can see. Also flashes the screen edges red when your character is hurt.
	Presentation only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SwingAnimation = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("SwingAnimation"))

local SwingFx = {}

local SHOW_DISTANCE = 200
local FADE_OUT = 0.1 -- seconds at the end where the swing blends back into walking

type Swing = { started: number, r15: boolean, joints: { [string]: any } } -- Motor6D or AnimationConstraint

local R15_JOINTS = { RightShoulder = true, RightElbow = true, LeftShoulder = true, Waist = true, Neck = true }
local R6_JOINTS = { ["Right Shoulder"] = true, ["Left Shoulder"] = true }

function SwingFx.start()
	local swings: { [Model]: Swing } = {}

	local function play(player: Player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = workspace.CurrentCamera
		if not (character and humanoid and root and root:IsA("BasePart")) then
			return
		end
		if camera and (root.Position - camera.CFrame.Position).Magnitude > SHOW_DISTANCE then
			return
		end
		local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
		local wanted = if r15 then R15_JOINTS else R6_JOINTS
		local joints = {}
		for _, item in character:GetDescendants() do
			if (item:IsA("Motor6D") or item:IsA("AnimationConstraint")) and wanted[item.Name] then
				joints[item.Name] = item
			end
		end
		swings[character] = { started = os.clock(), r15 = r15, joints = joints }
	end

	-- After the Animator has posed the body (walking, holding the tool), lay the swing
	-- over the arms and torso.
	RunService.Stepped:Connect(function()
		local now = os.clock()
		for character, swing in swings do
			local t = now - swing.started
			if t >= SwingAnimation.LENGTH or not character.Parent or character:GetAttribute("HB_Ragdolled") then
				swings[character] = nil
				continue
			end
			local weight = math.clamp((SwingAnimation.LENGTH - t) / FADE_OUT, 0, 1)
			local pose = if swing.r15 then SwingAnimation.sample(t) else SwingAnimation.sampleR6(t)
			for name, joint in swing.joints do
				local goal = pose[name]
				if goal and joint.Parent then
					joint.Transform = joint.Transform:Lerp(goal, weight)
				end
			end
		end
	end)

	local function watch(player: Player)
		player:GetAttributeChangedSignal("HB_SwingAt"):Connect(function()
			play(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	-- Red edges when you are hurt.
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "HollowboundHurt"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	flash.Parent = gui
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(200, 20, 20)
	edge.Thickness = 40
	edge.Transparency = 1
	edge.Parent = flash
	local function watchHealth(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not (humanoid and humanoid:IsA("Humanoid")) then
			return
		end
		local last = humanoid.Health
		humanoid.HealthChanged:Connect(function(health)
			if health < last and health > 0 then
				edge.Transparency = 0.35
				TweenService:Create(edge, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			end
			last = health
		end)
	end
	player.CharacterAdded:Connect(watchHealth)
	if player.Character then
		task.spawn(watchHealth, player.Character)
	end
end

return SwingFx
