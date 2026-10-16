--[[
	Server-timed poses for actions that have no animation clip yet (milestone 5). Server
	only. A pose is an offset on a few Motor6D joints (C0), blended in and out; the
	character's normal animations keep playing on top. Poses replicate to everyone.

	Driven by existing server state, so they always match the real action timing:
	  HB_Condition = "Downed"          -> Downed (hunched crawl)
	  HB_Action = "Bandage"/"Revive"/"SelfRescue" (Busy) -> that pose while it lasts
	  Combat and Abilities call pulse() for Swing, Windhook, and EchoLens.
	R15 joints are the target (Waist, RightShoulder, LeftShoulder). R6 joints get the same
	offsets, which look rougher; the README asks for R15 (Game Settings > Avatar).
	Fallback note: these are procedural stand-ins until real clips are chosen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))

local Poses = {}

local JOINTS = {
	Waist = { { "UpperTorso", "Waist" }, { "HumanoidRootPart", "RootJoint" } },
	RightShoulder = { { "RightUpperArm", "RightShoulder" }, { "Torso", "Right Shoulder" } },
	LeftShoulder = { { "LeftUpperArm", "LeftShoulder" }, { "Torso", "Left Shoulder" } },
}

local R = math.rad
local POSES = {
	Downed = { priority = 5, Waist = CFrame.Angles(R(-45), 0, 0), RightShoulder = CFrame.Angles(R(30), 0, 0), LeftShoulder = CFrame.Angles(R(30), 0, 0) },
	Swing = { priority = 4, RightShoulder = CFrame.Angles(R(150), 0, R(-15)) },
	SwingStrike = { priority = 4, RightShoulder = CFrame.Angles(R(35), 0, R(25)), Waist = CFrame.Angles(0, R(-20), 0) },
	Windhook = { priority = 3, RightShoulder = CFrame.Angles(R(-40), 0, 0), LeftShoulder = CFrame.Angles(R(-40), 0, 0) },
	EchoLens = { priority = 3, RightShoulder = CFrame.Angles(R(95), 0, 0) },
	Bandage = { priority = 2, RightShoulder = CFrame.Angles(R(70), 0, R(35)), LeftShoulder = CFrame.Angles(R(70), 0, R(-35)) },
	Revive = { priority = 2, Waist = CFrame.Angles(R(-35), 0, 0), RightShoulder = CFrame.Angles(R(60), 0, 0), LeftShoulder = CFrame.Angles(R(60), 0, 0) },
	SelfRescue = { priority = 2, RightShoulder = CFrame.Angles(R(55), 0, R(25)) },
}
local ACTION_POSE = { Bandage = "Bandage", Revive = "Revive", SelfRescue = "SelfRescue" }

local states: { [Model]: any } = setmetatable({}, { __mode = "k" }) :: any

local function findJoint(character: Model, options)
	for _, option in options do
		local part = character:FindFirstChild(option[1])
		local joint = part and part:FindFirstChild(option[2])
		if joint and joint:IsA("Motor6D") then
			return joint
		end
	end
	return nil
end

local function apply(character: Model)
	local state = states[character]
	if not state then
		return
	end
	local best, bestPriority = nil, -math.huge
	for name in state.active do
		local pose = POSES[name]
		if pose and pose.priority > bestPriority then
			best, bestPriority = pose, pose.priority
		end
	end
	local info = TweenInfo.new(Config.Poses.BlendSeconds)
	for jointName, joint in state.joints do
		if joint.Parent then
			local offset = best and best[jointName] or CFrame.identity
			TweenService:Create(joint, info, { C0 = state.base[jointName] * offset }):Play()
		end
	end
end

local function stateFor(player: Player)
	local character = player.Character
	return character and states[character], character
end

function Poses.set(player: Player, name: string, on: boolean)
	local state, character = stateFor(player)
	if not state then
		return
	end
	state.active[name] = if on then true else nil
	apply(character)
end

-- Holds a pose for `seconds`. A newer pulse of the same pose extends it.
function Poses.pulse(player: Player, name: string, seconds: number)
	local state, character = stateFor(player)
	if not state then
		return
	end
	state.tokens[name] = (state.tokens[name] or 0) + 1
	local token = state.tokens[name]
	state.active[name] = true
	apply(character)
	task.delay(seconds, function()
		if states[character] == state and state.tokens[name] == token then
			state.active[name] = nil
			apply(character)
		end
	end)
end

-- Melee: arm raised during the windup, then a quick strike, matching the server timing.
function Poses.swing(player: Player, windup: number)
	Poses.pulse(player, "Swing", windup)
	task.delay(windup, function()
		Poses.pulse(player, "SwingStrike", 0.25)
	end)
end

local function watchCharacter(player: Player, character: Model)
	if not Config.Poses.Enabled then
		return
	end
	character:WaitForChild("Humanoid", 10)
	task.wait(0.5) -- joints are built with the character
	if player.Character ~= character then
		return
	end
	local state = { joints = {}, base = {}, active = {}, tokens = {} }
	for name, options in JOINTS do
		local joint = findJoint(character, options)
		if joint then
			state.joints[name] = joint
			state.base[name] = joint.C0
		end
	end
	states[character] = state
	local function refreshAction()
		for _, pose in ACTION_POSE do
			state.active[pose] = nil
		end
		local action = player:GetAttribute("HB_Action")
		if action and ACTION_POSE[action] then
			state.active[ACTION_POSE[action]] = true
		end
		apply(character)
	end
	local function refreshCondition()
		state.active.Downed = if player:GetAttribute("HB_Condition") == "Downed" then true else nil
		apply(character)
	end
	local connections = {
		player:GetAttributeChangedSignal("HB_Action"):Connect(refreshAction),
		player:GetAttributeChangedSignal("HB_Condition"):Connect(refreshCondition),
	}
	character.AncestryChanged:Connect(function()
		if not character.Parent then
			for _, connection in connections do
				connection:Disconnect()
			end
		end
	end)
	refreshAction()
	refreshCondition()
end

function Poses.start()
	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return Poses
