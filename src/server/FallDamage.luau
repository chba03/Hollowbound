--[[
	Fall damage and the ragdoll on a fatal fall. Server side.

	The server watches every character's vertical speed. A fall starts when a character
	drops faster than Config.Fall.FallingSpeed; its height is measured from the highest
	point before it. On landing (the fall speed stops), the drop decides the damage:

	  - up to SafeStuds: nothing
	  - SafeStuds to FatalStuds: damage rising with the drop
	  - FatalStuds or more (or damage that empties health): death, as a ragdoll

	Climbers on a rope never take fall damage, and teleports (going home, the night,
	getting on the rope) reset the measurement. Rope length no longer stops a fall
	(see RopeService): a long drop is what makes depth beyond your rope dangerous.
	Every number is in Config.Fall (Open).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Perks = require(Shared:WaitForChild("Perks"))
local ServerNet = require(script.Parent.ServerNet)

local FallDamage = {}

type State = {
	peakY: number,
	falling: boolean,
	lastPosition: Vector3,
}

local states: { [Player]: State } = {}

-- Turns the character into a ragdoll: every joint becomes a loose ball-and-socket
-- joint and the limbs collide with the ground. Works for Motor6D joints and the newer
-- AnimationConstraint joints.
function FallDamage.ragdoll(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
	end
	for _, joint in character:GetDescendants() do
		local a0: Attachment?, a1: Attachment?
		if joint:IsA("Motor6D") and joint.Part0 and joint.Part1 then
			if joint.Name == "RootJoint" or joint.Name == "Root" and joint.Part0.Name == "HumanoidRootPart" then
				continue -- keep the body attached to the root part
			end
			local first = Instance.new("Attachment")
			first.Name = "RagdollA0"
			first.CFrame = joint.C0
			first.Parent = joint.Part0
			local second = Instance.new("Attachment")
			second.Name = "RagdollA1"
			second.CFrame = joint.C1
			second.Parent = joint.Part1
			a0, a1 = first, second
			joint.Enabled = false
		elseif joint:IsA("AnimationConstraint") then
			a0, a1 = joint.Attachment0, joint.Attachment1
			joint.Enabled = false
		end
		if a0 and a1 then
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "RagdollSocket"
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 60
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -40
			socket.TwistUpperAngle = 40
			socket.Parent = a0.Parent
		end
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = part.Name ~= "HumanoidRootPart"
		end
	end
end

local function meters(studs: number): number
	return math.floor(studs * Config.Display.MetersPerStud + 0.5)
end

local function land(player: Player, humanoid: Humanoid, drop: number)
	local cfg = Config.Fall
	local scale = Perks.fall(player) -- Featherfall pass
	local safe, fatalHeight = cfg.SafeStuds * scale, cfg.FatalStuds * scale
	if drop <= safe then
		return
	end
	local fatal = drop >= fatalHeight
	if not fatal then
		local t = (drop - safe) / (fatalHeight - safe)
		humanoid:TakeDamage(humanoid.MaxHealth * cfg.MaxNonFatalDamage * t ^ 1.3)
		fatal = humanoid.Health <= 0
	end
	if fatal then
		local character = humanoid.Parent :: Model
		FallDamage.ragdoll(character)
		humanoid.Health = 0
		ServerNet.notify(player, `You fell {meters(drop)} m. That was too far.`, "error")
		print(`[Hollowbound] {player.Name} died from a {math.floor(drop)}-stud fall`)
	else
		ServerNet.notify(player, `Hard landing: you fell {meters(drop)} m.`, "error")
	end
end

local function step(player: Player, state: State)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	local position = root.Position
	local vy = root.AssemblyLinearVelocity.Y
	local cfg = Config.Fall

	-- On the rope, or teleported (home, night, rope attach): start measuring afresh.
	local jumped = (position - state.lastPosition).Magnitude > cfg.TeleportStuds
	state.lastPosition = position
	if player:GetAttribute("HB_OnRope") == true or jumped then
		state.peakY = position.Y
		state.falling = false
		return
	end

	if state.falling then
		state.peakY = math.max(state.peakY, position.Y)
		if vy > -cfg.LandedSpeed then
			state.falling = false
			land(player, humanoid, state.peakY - position.Y)
			state.peakY = position.Y
		end
	elseif vy < -cfg.FallingSpeed then
		state.falling = true -- peakY holds the highest point before the drop
	elseif vy > 0.5 then
		state.peakY = math.max(state.peakY, position.Y) -- rising (a jump): track the top
	else
		state.peakY = position.Y -- on the ground
	end
end

function FallDamage.start()
	local function track(player: Player)
		local function reset()
			states[player] = { peakY = -math.huge, falling = false, lastPosition = Vector3.zero }
		end
		reset()
		player.CharacterAdded:Connect(function(character)
			reset()
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.BreakJointsOnDeath = false -- a fatal fall ragdolls instead
			end
		end)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	RunService.Heartbeat:Connect(function()
		for player, state in states do
			step(player, state)
		end
	end)
	print(string.format(
		"[Hollowbound] Fall damage: safe up to %d m, fatal from %d m",
		meters(Config.Fall.SafeStuds),
		meters(Config.Fall.FatalStuds)
	))
end

return FallDamage
