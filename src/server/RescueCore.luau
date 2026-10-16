--[[
	Who is reviving whom. Pure; server only. One helper per downed player at a time,
	tied to that player's current down token, so several helpers can never complete
	several revives (or heal twice) for the same down.
]]

local RescueCore = {}

function RescueCore.new()
	return { byTarget = {}, byHelper = {} }
end

-- Returns (true) or (false, "AlreadyBeingRevived" | "HelperBusy" | "SelfRevive").
function RescueCore.claim(r, targetKey, helperKey, token: number): (boolean, string?)
	if targetKey == helperKey then
		return false, "SelfRevive"
	end
	if r.byTarget[targetKey] then
		return false, "AlreadyBeingRevived"
	end
	if r.byHelper[helperKey] then
		return false, "HelperBusy"
	end
	r.byTarget[targetKey] = { helper = helperKey, token = token }
	r.byHelper[helperKey] = targetKey
	return true, nil
end

function RescueCore.release(r, targetKey)
	local entry = r.byTarget[targetKey]
	if entry then
		r.byHelper[entry.helper] = nil
		r.byTarget[targetKey] = nil
	end
end

function RescueCore.releaseHelper(r, helperKey)
	local targetKey = r.byHelper[helperKey]
	if targetKey ~= nil then
		RescueCore.release(r, targetKey)
	end
end

function RescueCore.entry(r, targetKey)
	return r.byTarget[targetKey]
end

function RescueCore.targetOf(r, helperKey)
	return r.byHelper[helperKey]
end

return RescueCore
