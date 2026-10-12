--[[
	The rope animations, defined in code: the climber holds the rope in both hands in
	front of the chest, legs gripping below.

	  hang  still on the rope, right hand above left
	  down  hand over hand downward: each hand grips while the body slides past it, then
	        lets go and reaches below the other hand
	  up    hand over hand upward: each hand pulls down to the chest, then reaches up;
	        the legs step up the rope

	build(mode) turns a mode into a real KeyframeSequence (an R15 animation). The client
	(RopePose) registers these at runtime so they play without being published. To publish
	them instead (optional), run this in Studio's command bar in edit mode:

	  require(game.ReplicatedStorage.HollowboundShared.RopeAnimations).export()

	then right-click each KeyframeSequence in ServerStorage > HollowboundRopeAnimations,
	choose "Save to Roblox", and paste the ids into Config.Rope.Animations.

	pose() is also used directly as a fallback for rigs the animations cannot drive.
]]

local Config = require(script.Parent.Config)

local RopeAnimations = {}

export type Pose = { [string]: CFrame }

local rad = math.rad

-- R15 joint name -> the part it moves (the joint's Part1, which is also the Pose name).
RopeAnimations.R15_JOINTS = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
	RightHip = "RightUpperLeg",
	RightKnee = "RightLowerLeg",
	LeftHip = "LeftUpperLeg",
	LeftKnee = "LeftLowerLeg",
	RightAnkle = "RightFoot",
	LeftAnkle = "LeftFoot",
}

-- R6 joints (all held by the Torso).
RopeAnimations.R6_JOINTS = {
	["Right Shoulder"] = "Torso",
	["Left Shoulder"] = "Torso",
	["Right Hip"] = "Torso",
	["Left Hip"] = "Torso",
}

-- The R15 body as a tree of { part, joint, children } under HumanoidRootPart, the
-- shape a KeyframeSequence's Poses must follow.
local TREE = {
	part = "LowerTorso",
	joint = "Root",
	children = {
		{
			part = "UpperTorso",
			joint = "Waist",
			children = {
				{ part = "Head", joint = "Neck" },
				{ part = "RightUpperArm", joint = "RightShoulder", children = { { part = "RightLowerArm", joint = "RightElbow" } } },
				{ part = "LeftUpperArm", joint = "LeftShoulder", children = { { part = "LeftLowerArm", joint = "LeftElbow" } } },
			},
		},
		{
			part = "RightUpperLeg",
			joint = "RightHip",
			children = { { part = "RightLowerLeg", joint = "RightKnee", children = { { part = "RightFoot", joint = "RightAnkle" } } } },
		},
		{
			part = "LeftUpperLeg",
			joint = "LeftHip",
			children = { { part = "LeftLowerLeg", joint = "LeftKnee", children = { { part = "LeftFoot", joint = "LeftAnkle" } } } },
		},
	},
}

-- Loop lengths (seconds) and keyframes per loop. One loop of "up" or "down" is one
-- stroke of each hand; RopePose speeds the loops up with the climber's speed.
RopeAnimations.CLIPS = {
	hang = { length = 2, keys = 2 },
	down = { length = 1, keys = 12 },
	up = { length = 1, keys = 12 },
}

-- Studs of rope one loop covers (two hand strokes). RopePose plays the loop at
-- speed / STROKE_STUDS loops per second, so the hands keep pace with the rope.
RopeAnimations.STROKE_STUDS = 8

-- One hand's height on the rope relative to the body over a loop t (0..1), -1 low to 1
-- high. The hand grips for most of the loop and moves with the rope, then lets go and
-- quickly reaches for a new grip.
--   climbing: the gripping hand pulls down to the chest (slow), then reaches up (quick)
--   descending: the body slides down past the gripping hand, so it rises toward the
--   head (slow), then lets go and reaches down below the other hand (quick)
local GRIP = 0.7 -- share of the loop spent gripping
local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end
local function handHeight(t: number, climbing: boolean): number
	t %= 1
	local rising -- the descending motion; climbing is its mirror
	if t < GRIP then
		rising = -1 + 2 * smooth(t / GRIP)
	else
		rising = 1 - 2 * smooth((t - GRIP) / (1 - GRIP))
	end
	return if climbing then -rising else rising
end

-- Body measurements of a standard R15 character, in studs, for placing the hands.
local LEAN = rad(14) -- the climber leans back from the rope
local WAIST = rad(-4) -- with a slight curl toward it
local SHOULDER_UP = 1.6 -- shoulders above the Root joint
local GRIP_SIDE = 0.85 -- each grip sits this far in from its shoulder: the hands close
-- around the rope from either side, almost touching (shoulders are about 1 stud out)
local UPPER_ARM = 1.0 -- shoulder to elbow
local FOREARM = 1.3 -- elbow to the middle of the grip

-- Shoulder swing, elbow bend, and inward turn that put a hand on the rope `up` studs
-- above the shoulder, with the rope `forward` studs in front. Solved exactly for the
-- joint order CFrame.Angles(swing, 0, -inward) then the elbow: the elbow bend sets the
-- shoulder-to-grip distance, the inward turn sets the sideways reach, and the swing
-- points the arm at the grip. Out-of-reach grips get a nearly straight arm.
-- Returns the swing in world terms (from hanging straight down), elbow, inward.
local function reach(up: number, forward: number): (number, number, number)
	local span = math.sqrt(up * up + forward * forward + GRIP_SIDE * GRIP_SIDE)
	local d = math.min(span, UPPER_ARM + FOREARM - 0.02)
	local cosElbow = (UPPER_ARM ^ 2 + FOREARM ^ 2 - d ^ 2) / (2 * UPPER_ARM * FOREARM)
	local elbow = math.pi - math.acos(math.clamp(cosElbow, -1, 1))
	-- The arm in its own plane before turning: down and forward from the shoulder.
	local down = -(UPPER_ARM + FOREARM * math.cos(elbow))
	local ahead = -FOREARM * math.sin(elbow)
	local inward = math.asin(math.clamp(GRIP_SIDE / math.abs(down), -1, 1))
	local swing = math.atan2(-forward, up) - math.atan2(ahead, down * math.cos(inward))
	return swing, elbow, inward
end

-- Joint rotations in each R15 joint's own frame. +X swings a limb forward and up from
-- hanging, tips the torso back, bends elbows, and tips the head up; -X bends knees.
-- Each hand is placed on the rope by reach(), so the hands stay on it in every mode.
--   phase: loop position (radians); mode: "hang" | "down" | "up"
function RopeAnimations.pose(phase: number, mode: string, _amount: number): Pose
	local t = (phase / (2 * math.pi)) % 1
	-- Grip heights above the shoulders, per hand. handHeight gives -1..1.
	local rightUp, leftUp, neck, legSwing
	if mode == "up" then
		rightUp = 1.05 + 0.45 * handHeight(t, true)
		leftUp = 1.05 + 0.45 * handHeight(t + 0.5, true)
		neck, legSwing = 12, 20 -- looking up; legs step up the rope
	elseif mode == "down" then
		rightUp = 0.95 + 0.35 * handHeight(t, false)
		leftUp = 0.95 + 0.35 * handHeight(t + 0.5, false)
		neck, legSwing = -16, 6 -- looking down; legs mostly wrapped and still
	else
		rightUp, leftUp = 1.35, 0.7 -- both hands holding, right above left
		neck, legSwing = -6, 0
	end

	-- The rope's distance in front of the shoulders: the hold offset, plus however far
	-- the lean carries the shoulders back.
	local tilt = LEAN + WAIST
	local forward = Config.Rope.HoldOffset + SHOULDER_UP * math.sin(tilt)
	local function arm(up: number): (number, number, number)
		local shoulder, elbow, inward = reach(up, forward)
		return shoulder - tilt, elbow, inward -- the torso is tilted back; undo that
	end
	local rightShoulder, rightElbow, rightIn = arm(rightUp)
	local leftShoulder, leftElbow, leftIn = arm(leftUp)

	-- Legs follow the opposite hand, like climbing a ladder: right hand high, left knee up.
	local rightHigh = (rightUp - leftUp) / 0.9
	local rightLeg = -rightHigh * legSwing
	local leftLeg = rightHigh * legSwing

	return {
		Root = CFrame.Angles(LEAN, 0, 0),
		Waist = CFrame.Angles(WAIST, 0, 0),
		Neck = CFrame.Angles(rad(neck), 0, 0),
		RightShoulder = CFrame.Angles(rightShoulder, 0, -rightIn),
		RightElbow = CFrame.Angles(rightElbow, 0, 0),
		LeftShoulder = CFrame.Angles(leftShoulder, 0, leftIn),
		LeftElbow = CFrame.Angles(leftElbow, 0, 0),
		RightHip = CFrame.Angles(rad(18 + rightLeg), 0, rad(-6)),
		RightKnee = CFrame.Angles(rad(-(38 + rightLeg)), 0, 0),
		LeftHip = CFrame.Angles(rad(18 + leftLeg), 0, rad(6)),
		LeftKnee = CFrame.Angles(rad(-(38 + leftLeg)), 0, 0),
		RightAnkle = CFrame.Angles(rad(10), 0, 0),
		LeftAnkle = CFrame.Angles(rad(10), 0, 0),
	}
end

-- R6 limbs rotate about the joint's Z axis; right side positive is forward, left side
-- negative is forward. Arms and legs only.
function RopeAnimations.r6Pose(phase: number, mode: string, _amount: number): Pose
	local t = (phase / (2 * math.pi)) % 1
	local moving = mode ~= "hang"
	local right = if moving then handHeight(t, mode == "up") else 0.7
	local left = if moving then handHeight(t + 0.5, mode == "up") else -0.3
	return {
		["Right Shoulder"] = CFrame.Angles(0, 0, rad(130 + 35 * right)),
		["Left Shoulder"] = CFrame.Angles(0, 0, -rad(130 + 35 * left)),
		["Right Hip"] = CFrame.Angles(0, 0, rad(25 + 15 * left)),
		["Left Hip"] = CFrame.Angles(0, 0, -rad(25 + 15 * right)),
	}
end

local function addPoses(parent: Instance, node, pose: Pose)
	local p = Instance.new("Pose")
	p.Name = node.part
	p.CFrame = pose[node.joint] or CFrame.identity
	p.EasingStyle = Enum.PoseEasingStyle.Linear
	p.Weight = 1
	p.Parent = parent
	for _, child in node.children or {} do
		addPoses(p, child, pose)
	end
end

-- A looping R15 KeyframeSequence for one mode ("hang" | "down" | "up").
function RopeAnimations.build(mode: string): KeyframeSequence
	local clip = RopeAnimations.CLIPS[mode]
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = "Abseil_" .. mode
	sequence.Loop = true
	sequence.Priority = Enum.AnimationPriority.Action4
	for i = 0, clip.keys do
		local t = i / clip.keys
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = t * clip.length
		local root = Instance.new("Pose")
		root.Name = "HumanoidRootPart"
		root.Weight = 0
		root.Parent = keyframe
		addPoses(root, TREE, RopeAnimations.pose(t * 2 * math.pi, mode, 1))
		keyframe.Parent = sequence
	end
	return sequence
end

-- Edit mode only: puts the three sequences in ServerStorage for publishing.
function RopeAnimations.export(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "HollowboundRopeAnimations"
	for mode in RopeAnimations.CLIPS do
		RopeAnimations.build(mode).Parent = folder
	end
	folder.Parent = game:GetService("ServerStorage")
	print("[Hollowbound] Rope animations exported to ServerStorage.HollowboundRopeAnimations")
	return folder
end

return RopeAnimations
