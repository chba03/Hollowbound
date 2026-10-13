--[[
	The Hauling Rig on every base: where players train Speed, the competitive stat that
	sets climb speed. Server side. Fully AFK (project owner):

	  - The "Haul rope" prompt on your own rig's rope (HaulHandle) locks your character
	    in place facing the rope (root anchored at a fixed spot) and starts hauling.
	  - While locked in, the rig pulls by itself every Config.Hauling.PullInterval.
	    Speed per pull = PullGain x your climb speed upgrade multiplier
	    (Config.Rope.SpeedLevels) x perks.
	  - Moving or jumping (client sends Net.HaulStop), dying, or leaving lets you go.

	Every pull bumps the plot's HaulCount attribute (clients hoist the crate) and the
	player's HB_HaulPullAt (clients play the pulling pose). HB_Hauling is true while
	locked in.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Perks = require(Shared:WaitForChild("Perks"))
local Progression = require(Shared:WaitForChild("Progression"))
local Characters = require(script.Parent.Characters)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local ServerNet = require(script.Parent.ServerNet)

local Hauling = {}

type Session = {
	plot: Model,
	root: BasePart,
	lastPull: number,
}

local sessions: { [Player]: Session } = {}

-- Speed per pull for this player right now.
function Hauling.gainPerPull(player: Player): number
	local data = PlayerData.get(player)
	local level = if data then data.RopeSpeedLevel else 1
	return Config.Hauling.PullGain * Progression.value("RopeSpeed", level) * Perks.speedGain(player)
end

-- Where a hauler stands: in front of the rope's handle, facing it, on the ground.
local function haulSpot(handle: BasePart, root: BasePart): CFrame
	local back = handle.CFrame:VectorToWorldSpace(Vector3.new(0, 0, -Config.Hauling.StandOff))
	local position = handle.Position + Vector3.new(back.X, 0, back.Z)
	local character = root.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then humanoid.HipHeight + root.Size.Y / 2 else 3
	local floorY = handle.Position.Y - Config.Hauling.HandleHeight
	local stand = Vector3.new(position.X, floorY + hip, position.Z)
	return CFrame.lookAt(stand, Vector3.new(handle.Position.X, stand.Y, handle.Position.Z))
end

function Hauling.stop(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	if session.root.Parent then
		session.root.Anchored = false
	end
	player:SetAttribute("HB_Hauling", false)
end

local function start(player: Player, plot: Model)
	if sessions[player] then
		return
	end
	if Plots.get(player) ~= plot then
		ServerNet.notify(player, "This isn't your Hauling Rig.", "error")
		return
	end
	local handle = plot:FindFirstChild("HaulHandle")
	local root = Characters.liveRoot(player)
	if not (handle and handle:IsA("BasePart") and root) or player:GetAttribute("HB_OnRope") then
		return
	end
	if (root.Position - handle.Position).Magnitude > Config.Hauling.Range then
		return
	end
	-- Lock the character in place, facing the rope (hands free: put away any tool).
	root.AssemblyLinearVelocity = Vector3.zero
	local character = root.Parent :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end
	character:PivotTo(haulSpot(handle, root))
	root.Anchored = true
	sessions[player] = { plot = plot, root = root, lastPull = os.clock() }
	player:SetAttribute("HB_Hauling", true)
end

local function pull(player: Player, session: Session)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	data.Speed += Hauling.gainPerPull(player)
	PlayerData.publishSpeed(player)
	local count = session.plot:GetAttribute("HaulCount")
	session.plot:SetAttribute("HaulCount", (if typeof(count) == "number" then count else 0) + 1)
	player:SetAttribute("HB_HaulPullAt", workspace:GetServerTimeNow())
end

function Hauling.start()
	for _, plot in Plots.all() do
		local handle = plot:FindFirstChild("HaulHandle")
		if handle and handle:IsA("BasePart") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "HaulPrompt"
			prompt.ActionText = "Haul rope"
			prompt.ObjectText = "Hauling Rig"
			prompt.HoldDuration = 0.3
			prompt.MaxActivationDistance = Config.Hauling.Range
			prompt.RequiresLineOfSight = false
			prompt.Parent = handle
			prompt.Triggered:Connect(function(player)
				start(player, plot)
			end)
		end
	end

	ServerNet.on(Net.HaulStop, Hauling.stop)
	Players.PlayerRemoving:Connect(Hauling.stop)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			Hauling.stop(player)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterRemoving:Connect(function()
			Hauling.stop(player)
		end)
	end

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for player, session in sessions do
			local root = Characters.liveRoot(player)
			if root ~= session.root or Plots.get(player) ~= session.plot then
				Hauling.stop(player) -- died, respawned, or lost the plot
				continue
			end
			if now - session.lastPull >= Config.Hauling.PullInterval then
				session.lastPull = now
				pull(player, session)
			end
		end
	end)
end

return Hauling
