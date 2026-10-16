--[[
	Routes FieldAction requests (milestone 4): "Attack", "Supply", "Cancel". Server only.
	Only the action name is read; anything else the client sends is ignored. Requests are
	rate limited per player (Config.Requests.MaxPerSecond), on top of each action's own
	checks (cooldowns, timed actions, character state, session).

	Supply: a standing player starts a bandage; a downed player starts a self-rescue kit.
	Cancel: stops your own bandage or self-rescue (a revive stops when you let go).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Busy = require(script.Parent.Busy)
local Combat = require(script.Parent.Combat)
local Gear = require(script.Parent.Gear)
local Rescue = require(script.Parent.Rescue)
local ServerNet = require(script.Parent.ServerNet)
local Vitals = require(script.Parent.Vitals)

local FieldActions = {}

local buckets: { [Player]: { tokens: number, at: number } } = {}

local function allow(player: Player): boolean
	local now = os.clock()
	local rate = Config.Requests.MaxPerSecond
	local bucket = buckets[player] or { tokens = rate, at = now }
	buckets[player] = bucket
	bucket.tokens = math.min(rate, bucket.tokens + (now - bucket.at) * rate)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function FieldActions.handle(player: Player, action: any): (boolean, string)
	if not allow(player) then
		return false, ""
	end
	if action == "Attack" then
		return Combat.requestAttack(player)
	elseif action == "Supply" then
		if Vitals.condition(player) == "Downed" then
			return Rescue.beginSelfRescue(player)
		end
		return Gear.useBandage(player)
	elseif action == "Cancel" then
		local kind = Busy.kind(player)
		if kind == "Bandage" or kind == "SelfRescue" then
			Busy.cancel(player, "Cancelled.")
			return true, ""
		end
		return false, ""
	end
	return false, "Unknown action."
end

function FieldActions.start()
	ServerNet.onFieldAction(FieldActions.handle)
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return FieldActions
