--[[
	Climbing fatigue. Server side.

	Only for players carrying an unsecured relic of rank Config.Ascent.MinRank or higher
	(Eternal, Godly). Such a player has a low point: the deepest depth reached since they
	picked it up or last rested. Once they have climbed Config.Ascent.LimitMeters above
	it, they cannot climb higher until they rest in a camp (stand in its ring for
	RestSeconds), which moves the low point up to the camp. Being in town resets it. So a
	carrier at 135 m can rise to 35 m, then must rest at a camp before going higher.
	Everyone else climbs freely.

	Published for the client: HB_AscentCeiling, the shallowest depth in studs you may
	climb to (nil when the surface is in reach). RopeService enforces it on the rope.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Characters = require(script.Parent.Characters)
local Hollow = require(script.Parent.Hollow)
local ServerNet = require(script.Parent.ServerNet)

local Ascent = {}

local store

type State = { low: number, rest: number }

local states: { [Player]: State } = {}
local LIMIT_STUDS = Config.Ascent.LimitMeters / Config.Display.MetersPerStud

local function ceiling(state: State): number?
	local depth = state.low - LIMIT_STUDS
	return if depth > 0 then depth else nil
end

-- The highest world Y this player may climb to, or nil when there is no limit.
function Ascent.ceilingY(player: Player): number?
	local state = states[player]
	local center = Hollow.center()
	local depth = state and ceiling(state)
	if not depth or not center then
		return nil
	end
	return center.Y - depth
end

-- Carrying an unsecured relic rare enough to weigh you down?
local function burdened(player: Player): boolean
	for _, specimen in store:carried(player.UserId) do
		local tier = Config.RarityById[specimen.rarity]
		if not specimen.registered and tier and tier.rank >= Config.Ascent.MinRank then
			return true
		end
	end
	return false
end

local function update(player: Player, state: State, dt: number)
	local root = Characters.liveRoot(player)
	if not root then
		return
	end
	local depth = Hollow.measure(root.Position)
	local zone = player:GetAttribute("HB_Zone")
	if zone == "Town" or not depth or depth <= 0 or not burdened(player) then
		-- No limit; the count starts from wherever a rare relic is picked up.
		state.low, state.rest = math.max(depth or 0, 0), 0
		player:SetAttribute("HB_AscentCeiling", nil)
		return
	end
	state.low = math.max(state.low, depth)
	if zone == "Camp" then
		local tired = ceiling(state) ~= nil
		local wasRested = state.rest >= Config.Ascent.RestSeconds
		state.rest += dt
		if state.rest >= Config.Ascent.RestSeconds then
			state.low = depth
			if tired and not wasRested then
				ServerNet.notify(player, `Rested. You can climb another {Config.Ascent.LimitMeters} m.`, "success")
			end
		end
	else
		state.rest = 0
	end
	player:SetAttribute("HB_AscentCeiling", ceiling(state))
end

function Ascent.start(theStore)
	store = theStore
	local function track(player: Player)
		states[player] = { low = 0, rest = 0 }
		player.CharacterAdded:Connect(function()
			local state = states[player]
			if state then
				state.low, state.rest = 0, 0 -- respawns are at base
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

	task.spawn(function()
		while true do
			local dt = task.wait(Config.Ascent.CheckInterval)
			for player, state in states do
				update(player, state, dt)
			end
		end
	end)
end

return Ascent
