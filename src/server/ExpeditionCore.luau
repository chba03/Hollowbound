--[[
	Expedition lifecycle for one player. Pure; no Roblox services. Server only.

	phase: "Town" | "Exploring" | "AtCamp"
	  - Leaving town starts one run. Moving between the depths and camps keeps the same
	    run: a camp neither starts nor finishes one (Decided: a camp is a refuge only).
	  - Returning to town, or final death, finishes the run exactly once.
	  - There is no time limit on a run (Decided).
	Ending a run changes no relic: it never registers, appraises, activates, repairs,
	or recharges anything.

	Run ids come from a shared counter (makeRunId) so they never repeat on a server,
	and a delayed callback that remembers an old run id can always tell it is stale.
	Per-run allowances (self-rescues) live on the run, not on the character, so a new
	character inside the same run cannot reset them.
]]

local ExpeditionCore = {}

local PHASE_FOR_ZONE = {
	Town = "Town",
	Camp = "AtCamp",
	Depths = "Exploring",
}

function ExpeditionCore.new()
	return {
		phase = "Town",
		run = nil, -- { id, startedAt, selfRescuesUsed }
		known = false, -- false until the first zone reading
	}
end

--[[
	Feeds the zone the living character is in. Returns a list of events:
	  { kind = "RunStarted", runId }  |  { kind = "RunFinished", runId, reason = "Returned" }
	  { kind = "Phase", phase }
]]
function ExpeditionCore.onZone(e, zone: string, now: number, makeRunId: () -> number)
	local events = {}
	local phase = PHASE_FOR_ZONE[zone] or "Exploring"
	if phase == "Town" then
		if e.run then
			local id = e.run.id
			e.run = nil
			table.insert(events, { kind = "RunFinished", runId = id, reason = "Returned" })
		end
	elseif not e.run and (e.phase == "Town" or not e.known) then
		e.run = { id = makeRunId(), startedAt = now, selfRescuesUsed = 0 }
		table.insert(events, { kind = "RunStarted", runId = e.run.id })
	end
	e.known = true
	if phase ~= e.phase then
		e.phase = phase
		table.insert(events, { kind = "Phase", phase = phase })
	end
	return events
end

-- Final death (or any other forced end). Returns the finished run id, or nil if no
-- run was active (so repeated calls do nothing). The next character's first zone
-- reading decides the phase again: in town it waits for a departure; outside town
-- (a respawn point in the field) it starts a new run.
function ExpeditionCore.finish(e): number?
	if not e.run then
		return nil
	end
	local id = e.run.id
	e.run = nil
	e.known = false
	return id
end

function ExpeditionCore.runId(e): number?
	return e.run and e.run.id
end

-- Self-rescues left in the current run (0 outside a run).
function ExpeditionCore.selfRescuesLeft(e, limit: number): number
	if not e.run then
		return 0
	end
	return math.max(0, limit - e.run.selfRescuesUsed)
end

-- Records one successful self-rescue for the given run. Refuses a stale run id.
function ExpeditionCore.useSelfRescue(e, runId: number, limit: number): boolean
	if not e.run or e.run.id ~= runId or e.run.selfRescuesUsed >= limit then
		return false
	end
	e.run.selfRescuesUsed += 1
	return true
end

return ExpeditionCore
