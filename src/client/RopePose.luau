--[[
	The rope animation for players on a rope (see shared RopeAnimations for the moves:
	holding, hand over hand going down, hand over hand going up).

	Two sources:

	  1. Published ids in Config.Rope.Animations: played through the Animator on the
	     local character only; Roblox replicates character animations, so everyone sees
	     them.
	  2. Otherwise the built-in RopeAnimations pose, set directly on the joints each
	     frame on every nearby climber (every client does the same: everyone sees
	     everyone). Animations registered at runtime only play in Studio, so they are
	     not used: Studio and live servers look the same.

	The mode follows the climber's vertical speed, and the hop and climb loops speed up
	with it. Presentation only. The Output prints one line saying which source is used.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local RopeAnimations = require(Shared:WaitForChild("RopeAnimations"))

local RopePose = {}

local POSE_DISTANCE = 250 -- only animate climbers this close to the camera
local FADE = 0.25
local BLEND_IN = 6 -- per second, joint fallback only
local BLEND_OUT = 8

type Climber = {
	animator: Animator?,
	tracks: { [string]: AnimationTrack },
	playing: string?,
	joints: { [string]: any }, -- joint fallback: Motor6D or AnimationConstraint
	r15: boolean,
	weight: number,
	target: number,
	phase: number,
	smoothedVy: number,
}

local climbers: { [Model]: Climber } = {}
local animationIds: { [string]: string } = {} -- mode -> content id
local localOnly = false -- true when the ids are published (Roblox replicates them)

-- Finds the rig's joints by name anywhere in the character.
local function collectJoints(character: Model, r15: boolean): { [string]: any }
	local wanted: { [string]: string } = if r15 then RopeAnimations.R15_JOINTS else RopeAnimations.R6_JOINTS
	local joints = {}
	for _, item in character:GetDescendants() do
		if wanted[item.Name] and (item:IsA("Motor6D") or item:IsA("AnimationConstraint")) then
			joints[item.Name] = item
		end
	end
	return joints
end

local function loadTracks(animator: Animator): { [string]: AnimationTrack }
	local tracks = {}
	for mode, id in animationIds do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Action4
			tracks[mode] = track
		end
	end
	return tracks
end

local function newClimber(character: Model): Climber
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local r15 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local climber: Climber = {
		animator = animator,
		tracks = {},
		playing = nil,
		joints = {},
		r15 = r15,
		weight = 0,
		target = 1,
		phase = 0,
		smoothedVy = 0,
	}
	if animator and r15 and next(animationIds) then
		climber.tracks = loadTracks(animator)
	end
	if not next(climber.tracks) then
		climber.joints = collectJoints(character, r15)
	end
	return climber
end

local function stopTracks(climber: Climber)
	for _, track in climber.tracks do
		track:Stop(FADE)
	end
	climber.playing = nil
end

-- Loops per second for a climber moving at `speed` studs/s, so the hands keep pace with
-- the rope: faster climb-speed upgrades (and the faster slide down) mean faster hands.
local function loopRate(speed: number): number
	return math.clamp(speed / RopeAnimations.STROKE_STUDS, 0.6, 6)
end

-- Animator path: play the track for this mode, adjusting its speed.
local function driveTracks(climber: Climber, mode: string, speed: number)
	local track = climber.tracks[mode] or climber.tracks.hang
	if not track then
		return
	end
	if climber.playing ~= mode then
		for _, other in climber.tracks do
			if other ~= track and other.IsPlaying then
				other:Stop(FADE)
			end
		end
		if not track.IsPlaying then
			track:Play(FADE)
		end
		climber.playing = mode
	end
	if mode ~= "hang" then
		track:AdjustSpeed(loopRate(speed))
	end
end

-- Joint path: set the pose on the joints directly, blended by weight.
local function driveJoints(climber: Climber, mode: string, speed: number, dt: number)
	if mode ~= "hang" then
		climber.phase += loopRate(speed) * 2 * math.pi * dt
	end
	local amount = if mode == "hang" then 1 else math.clamp(speed / 12, 0.5, 1)
	local pose = if climber.r15
		then RopeAnimations.pose(climber.phase, mode, amount)
		else RopeAnimations.r6Pose(climber.phase, mode, amount)
	for name, joint in climber.joints do
		local goal = pose[name]
		if goal and joint.Parent then
			joint.Transform = joint.Transform:Lerp(goal, climber.weight)
		end
	end
end

-- Chooses where the animations come from. Returns a description for the Output.
local function prepareAnimations(): string
	local ids = Config.Rope.Animations
	local published = { hang = ids.Hang, down = ids.Descend, up = ids.Climb }
	for mode, id in published do
		if id ~= "" then
			animationIds[mode] = id
		end
	end
	if next(animationIds) then
		localOnly = true
		return "published animations from Config.Rope.Animations"
	end
	return "built-in pose set on the joints"
end

function RopePose.start()
	local source = prepareAnimations()
	print(`[Hollowbound] Rope animation: {source}`)

	local localPlayer = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local reportedLocal = false

	RunService.Stepped:Connect(function(_, dt)
		local eye = if camera then camera.CFrame.Position else Vector3.zero

		for _, player in Players:GetPlayers() do
			local character = player.Character
			if not character then
				continue
			end
			-- Published animations replicate by themselves; only drive our own character.
			if localOnly and player ~= localPlayer then
				continue
			end
			local onRope = player:GetAttribute("HB_OnRope") == true
				or player:GetAttribute("HB_Hauling") == true -- the Hauling Rig uses the same moves
			local root = character:FindFirstChild("HumanoidRootPart")
			local near = root ~= nil and root:IsA("BasePart") and (root.Position - eye).Magnitude <= POSE_DISTANCE
			local active = onRope and near
			local climber = climbers[character]
			if active and not climber then
				climber = newClimber(character)
				climbers[character] = climber
				if player == localPlayer and not reportedLocal then
					reportedLocal = true
					local tracks, joints = 0, 0
					for _ in climber.tracks do
						tracks += 1
					end
					for _ in climber.joints do
						joints += 1
					end
					print(`[Hollowbound] Rope animation on your character: {if climber.r15 then "R15" else "R6"}, {tracks} animation(s), {joints} joint(s) posed directly`)
				end
			end
			if climber then
				climber.target = if active then 1 else 0
			end
		end

		for character, climber in climbers do
			if not character.Parent then
				climbers[character] = nil
				continue
			end
			if climber.target == 0 then
				stopTracks(climber)
				climber.weight = math.max(0, climber.weight - BLEND_OUT * dt)
				if climber.weight <= 0 or next(climber.tracks) then
					climbers[character] = nil
					continue
				end
			else
				climber.weight = math.min(1, climber.weight + BLEND_IN * dt)
			end

			local root = character:FindFirstChild("HumanoidRootPart")
			local vy = if root and root:IsA("BasePart") then root.AssemblyLinearVelocity.Y else 0
			climber.smoothedVy += (vy - climber.smoothedVy) * math.min(1, dt * 8)
			local speed = math.abs(climber.smoothedVy)
			local mode = if climber.smoothedVy < -2 then "down" elseif climber.smoothedVy > 2 then "up" else "hang"
			local owner = Players:GetPlayerFromCharacter(character)
			if owner and owner:GetAttribute("HB_Hauling") == true and owner:GetAttribute("HB_OnRope") ~= true then
				-- At the Hauling Rig: standing, pulling hand over hand, feet planted.
				mode = "haul"
				speed = 16
			end

			if next(climber.tracks) then
				driveTracks(climber, mode, speed)
			else
				driveJoints(climber, mode, speed, dt)
			end
		end
	end)
end

return RopePose
