--[[
	One place that says whether a player may act right now.

	check(player): the saved profile is loaded and the session is still ours. Every
	gameplay mutation needs this (milestone 3).
	checkActive(player): check() plus a standing character (Alive, not Downed or Dead).
	Pickups, registration, service, relic actions, abilities, attacks, bandages, supply
	refills, and loot all need this (milestone 4: downed players can only wait for help
	or use a self-rescue kit).
]]

local Guard = {}

local sessions
local conditionOf: ((Player) -> string)? = nil

function Guard.setSessions(theSessions)
	sessions = theSessions
end

function Guard.sessions()
	return sessions
end

-- provider(player) -> "Alive" | "Downed" | "Dead"
function Guard.setConditionProvider(provider: (Player) -> string)
	conditionOf = provider
end

-- (true) or (false, playerFacingReason)
function Guard.check(player: Player): (boolean, string?)
	if not sessions then
		return false, "The server is still starting."
	end
	return sessions:canMutate(player.UserId)
end

function Guard.checkActive(player: Player): (boolean, string?)
	local ok, reason = Guard.check(player)
	if not ok then
		return false, reason
	end
	local condition = if conditionOf then conditionOf(player) else "Alive"
	if condition == "Downed" then
		return false, "You are down. Wait for a revive or use a self-rescue kit."
	elseif condition ~= "Alive" then
		return false, "You cannot do that right now."
	end
	return true
end

return Guard
