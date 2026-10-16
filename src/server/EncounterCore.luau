--[[
	One guardian encounter and its relic cache. Pure; the clock and the reward factory
	are passed in. Server only.

	Cycle: Guarded (guardian alive, cache locked) -> Unlocked (guardian defeated, the
	reward lies in the cache as a normal world relic) -> Cooldown (reward claimed) ->
	the next cycle after respawnSeconds. Every cycle has its own id; callbacks that
	carry an old cycle id are ignored.

	The reward is generated at most once per cycle, at the moment the guardian is
	defeated, and only then. Whoever picks it up first owns it (normal pickup flow); it is
	never assigned to the player who landed the last hit. Players leaving never resets an
	encounter. An environmental loss of the guardian (fell out of the world) gives no
	reward and schedules a reset.
]]

local EncounterCore = {}

function EncounterCore.new(id: string)
	return { id = id, cycle = 0, state = "Idle", rewardId = nil, resetAt = nil }
end

function EncounterCore.beginCycle(e, now: number): number
	e.cycle += 1
	e.state = "Guarded"
	e.rewardId = nil
	e.resetAt = nil
	return e.cycle
end

function EncounterCore.isLocked(e): boolean
	return e.state ~= "Unlocked"
end

--[[
	The guardian of `cycle` was defeated. makeReward() creates the specimen and returns
	its id; it is called at most once per cycle. Returns (true, rewardId) the first time,
	(false, reason) for stale or repeated calls.
]]
function EncounterCore.guardianDefeated(e, cycle: number, makeReward: () -> string?): (boolean, string?)
	if cycle ~= e.cycle then
		return false, "StaleCycle"
	end
	if e.state ~= "Guarded" then
		return false, "AlreadyDefeated"
	end
	e.state = "Unlocked"
	e.rewardId = makeReward()
	return true, e.rewardId
end

-- The guardian of `cycle` was lost without being defeated (no reward).
function EncounterCore.guardianLost(e, cycle: number, now: number, resetSeconds: number): boolean
	if cycle ~= e.cycle or e.state ~= "Guarded" then
		return false
	end
	e.state = "Cooldown"
	e.resetAt = now + resetSeconds
	return true
end

-- A relic was claimed. Starts the cooldown only if it is this cycle's reward.
function EncounterCore.rewardClaimed(e, specimenId: string, now: number, respawnSeconds: number): boolean
	if e.state ~= "Unlocked" or e.rewardId == nil or e.rewardId ~= specimenId then
		return false
	end
	e.state = "Cooldown"
	e.resetAt = now + respawnSeconds
	return true
end

function EncounterCore.resetDue(e, now: number): boolean
	return (e.state == "Cooldown" or e.state == "Idle") and (e.resetAt == nil or now >= e.resetAt)
end

-- Weighted pick from Config.Encounters.RewardTable. roll in [0, 1).
function EncounterCore.pickReward(rewardTable, roll: number)
	local total = 0
	for _, entry in rewardTable do
		total += entry.weight
	end
	local target = roll * total
	local acc = 0
	for _, entry in rewardTable do
		acc += entry.weight
		if target < acc then
			return entry
		end
	end
	return rewardTable[#rewardTable]
end

return EncounterCore
