--[[
	One place that says whether a player's gameplay mutations are allowed right now.
	Every pickup, registration, service, appraisal, activation, equip, and ability use
	asks Guard first. Mutations are refused until the player's saved profile has loaded,
	and again if the session is lost.
]]

local Guard = {}

local sessions

function Guard.setSessions(theSessions)
	sessions = theSessions
end

function Guard.sessions()
	return sessions
end

-- (true) or (false, playerFacingReason)
function Guard.check(player: Player): (boolean, string?)
	if not sessions then
		return false, "The server is still starting."
	end
	return sessions:canMutate(player.UserId)
end

return Guard
