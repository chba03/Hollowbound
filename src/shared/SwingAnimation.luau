--[[
	The pickaxe swing, defined in code: the right arm winds the pickaxe up overhead with
	the body turning back, brings it down hard with a forward lean, and recovers. Only
	the arms, waist, and neck are animated, so walking keeps working during a swing.
	The strike lands at about STRIKE seconds, matching Config.Pickaxes.HitDelay.

	sample() / sampleR6() give the pose at a time, for setting the joints directly
	(client SwingFx). That works on live servers, where animations registered at
	runtime do not. build() is kept for publishing it as a real animation.
]]

local RopeAnimations = require(script.Parent.RopeAnimations)

local SwingAnimation = {}

local A = CFrame.Angles
local LENGTH = 0.45
SwingAnimation.STRIKE = 0.2

local KEYS = {
	{ 0, {
		RightShoulder = A(math.rad(40), 0, 0),
		RightElbow = A(math.rad(30), 0, 0),
		Waist = A(0, 0, 0),
	} },
	-- Wind up: pickaxe high behind the head, body turned back.
	{ 0.11, {
		RightShoulder = A(math.rad(168), 0, math.rad(-8)),
		RightElbow = A(math.rad(95), 0, 0),
		LeftShoulder = A(math.rad(55), 0, math.rad(15)),
		Waist = A(math.rad(10), math.rad(-14), 0),
		Neck = A(math.rad(6), 0, 0),
	}, Enum.PoseEasingStyle.Cubic },
	-- Strike: down and through, leaning in.
	{ SwingAnimation.STRIKE, {
		RightShoulder = A(math.rad(50), 0, 0),
		RightElbow = A(math.rad(4), 0, 0),
		LeftShoulder = A(math.rad(20), 0, 0),
		Waist = A(math.rad(-18), math.rad(10), 0),
		Neck = A(math.rad(-10), 0, 0),
	} },
	-- Recover.
	{ LENGTH, {
		RightShoulder = A(math.rad(35), 0, 0),
		RightElbow = A(math.rad(25), 0, 0),
		LeftShoulder = A(math.rad(5), 0, 0),
		Waist = A(math.rad(-3), 0, 0),
		Neck = A(0, 0, 0),
	}, Enum.PoseEasingStyle.Cubic },
}

SwingAnimation.LENGTH = LENGTH

-- The same swing for R6 rigs: shoulder raise in degrees (right, left), per key time.
local R6_KEYS = {
	{ 0, 40, 0 },
	{ 0.11, 170, 50 },
	{ SwingAnimation.STRIKE, 50, 20 },
	{ LENGTH, 35, 5 },
}

local function blend(a: number, b: number, alpha: number, easing: Enum.PoseEasingStyle?): number
	if easing == Enum.PoseEasingStyle.Cubic then
		alpha = alpha * alpha * (3 - 2 * alpha)
	end
	return a + (b - a) * alpha
end

-- The R15 pose `t` seconds into the swing, joint name -> Transform. Joints a key
-- leaves out hold their previous key's pose.
function SwingAnimation.sample(t: number): { [string]: CFrame }
	t = math.clamp(t, 0, LENGTH)
	local pose = {}
	for i = 1, #KEYS - 1 do
		local from, to = KEYS[i], KEYS[i + 1]
		if t <= to[1] or i == #KEYS - 1 then
			local alpha = math.clamp((t - from[1]) / (to[1] - from[1]), 0, 1)
			if to[3] == Enum.PoseEasingStyle.Cubic then
				alpha = alpha * alpha * (3 - 2 * alpha)
			end
			for joint, goal in to[2] do
				local start = from[2][joint] or CFrame.identity
				pose[joint] = start:Lerp(goal, alpha)
			end
			for joint, start in from[2] do
				if not pose[joint] then
					pose[joint] = start
				end
			end
			return pose
		end
	end
	return pose
end

-- The R6 pose `t` seconds into the swing.
function SwingAnimation.sampleR6(t: number): { [string]: CFrame }
	t = math.clamp(t, 0, LENGTH)
	for i = 1, #R6_KEYS - 1 do
		local from, to = R6_KEYS[i], R6_KEYS[i + 1]
		if t <= to[1] or i == #R6_KEYS - 1 then
			local alpha = math.clamp((t - from[1]) / (to[1] - from[1]), 0, 1)
			local right = blend(from[2], to[2], alpha, Enum.PoseEasingStyle.Cubic)
			local left = blend(from[3], to[3], alpha, Enum.PoseEasingStyle.Cubic)
			return {
				["Right Shoulder"] = CFrame.Angles(0, 0, math.rad(right)),
				["Left Shoulder"] = CFrame.Angles(0, 0, -math.rad(left)),
			}
		end
	end
	return {}
end

function SwingAnimation.build(): KeyframeSequence
	return RopeAnimations.sequence("PickaxeSwing", KEYS, false, Enum.AnimationPriority.Action4)
end

return SwingAnimation
