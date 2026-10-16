--[[
	Creature decision logic shared by every variant. Pure: the server measures the
	world (distances, line of sight, zones) and passes a perception table; the brain
	returns what to do. Server only.

	States: Idle, Patrol, Pursue, Windup (telegraph), Recover (the opening after a
	strike), Return (back to the den; ignores targets until home), Dead.

	Rules:
	  - Targets must be Alive (never Downed or Dead), outside protected zones, and inside
	    the leash around the den. Standing explorers are always preferred; a downed
	    explorer is left alone, which gives others a chance to revive them.
	  - New targets are acquired only when noticed (seen inside the field of view and
	    detection radius, or heard close by). A pursued target is lost after being out
	    of sight for loseSightSeconds, after repeated path failures, or when it leaves
	    the leash or enters a protected zone.
	  - Reaching the den after a Return is an encounter reset (reset = true): the
	    server restores full health, so hit-and-retreat farming does not work.

	c = { state, targetKey?, stateUntil, lastSeenAt, patrolUntil }
	p = {
		now, distanceFromHome, selfProtected, patrolArrived, pathFailures, maxPathFailures,
		targets = { [key] = { distance, visible, noticeable, protected, condition, homeDistance } },
	}
	Returns { move = "Target"|"Home"|"Patrol"|"Stop", telegraph?, strike?, reset?, newPatrol? }
]]

local CreatureBrain = {}

local HOME_RADIUS = 3
local PATROL_PAUSE = 3

function CreatureBrain.new(now: number)
	return { state = "Idle", targetKey = nil, stateUntil = now, lastSeenAt = now, patrolUntil = now + PATROL_PAUSE }
end

local function acceptable(t, cfg): boolean
	return t ~= nil and t.condition == "Alive" and not t.protected and t.homeDistance <= cfg.leashRadius
end

-- Nearest noticeable, acceptable target, or nil. `exclude` skips one key (a target
-- just given up as unreachable, so it is not immediately chosen again).
function CreatureBrain.pickTarget(p, cfg, exclude: any?)
	local bestKey, bestDistance = nil, math.huge
	for key, t in p.targets do
		if key ~= exclude and acceptable(t, cfg) and t.noticeable and t.distance < bestDistance then
			bestKey, bestDistance = key, t.distance
		end
	end
	return bestKey
end

local function startReturn(c)
	c.state = "Return"
	c.targetKey = nil
	return { move = "Home" }
end

function CreatureBrain.step(c, p, cfg)
	local now = p.now
	if c.state == "Dead" then
		return { move = "Stop" }
	end
	if p.selfProtected and c.state ~= "Return" then
		return startReturn(c)
	end

	if c.state == "Windup" then
		if now >= c.stateUntil then
			c.state = "Recover"
			c.stateUntil = now + cfg.recovery
			return { move = "Stop", strike = true }
		end
		return { move = "Stop" }
	end

	if c.state == "Recover" then
		if now < c.stateUntil then
			return { move = "Stop" }
		end
		local t = c.targetKey and p.targets[c.targetKey]
		if acceptable(t, cfg) then
			c.state = "Pursue"
		else
			c.targetKey = CreatureBrain.pickTarget(p, cfg)
			if c.targetKey then
				c.state = "Pursue"
				c.lastSeenAt = now
			else
				return startReturn(c)
			end
		end
	end

	if c.state == "Return" then
		if p.distanceFromHome <= HOME_RADIUS then
			c.state = "Idle"
			c.patrolUntil = now + PATROL_PAUSE
			return { move = "Stop", reset = true }
		end
		return { move = "Home" }
	end

	if c.state == "Pursue" then
		if p.distanceFromHome > cfg.leashRadius then
			return startReturn(c)
		end
		local t = c.targetKey and p.targets[c.targetKey]
		if t and t.visible then
			c.lastSeenAt = now
		end
		local unreachable = (p.pathFailures or 0) >= (p.maxPathFailures or 3)
		local lost = unreachable or not acceptable(t, cfg) or now - c.lastSeenAt > cfg.loseSightSeconds
		if lost then
			c.targetKey = CreatureBrain.pickTarget(p, cfg, if unreachable then c.targetKey else nil)
			if not c.targetKey then
				return startReturn(c)
			end
			c.lastSeenAt = now
			t = p.targets[c.targetKey]
		end
		if t.visible and t.distance <= cfg.attackRange then
			c.state = "Windup"
			c.stateUntil = now + cfg.windup
			return { move = "Stop", telegraph = true }
		end
		return { move = "Target" }
	end

	-- Idle or Patrol: look for someone to chase.
	local key = CreatureBrain.pickTarget(p, cfg)
	if key then
		c.state = "Pursue"
		c.targetKey = key
		c.lastSeenAt = now
		return { move = "Target" }
	end
	if c.state == "Patrol" then
		if p.patrolArrived then
			c.state = "Idle"
			c.patrolUntil = now + PATROL_PAUSE
			return { move = "Stop" }
		end
		return { move = "Patrol" }
	end
	if now >= c.patrolUntil and (cfg.patrolRadius or 0) > 0 then
		c.state = "Patrol"
		return { move = "Patrol", newPatrol = true }
	end
	return { move = "Stop" }
end

-- Death is final for this creature instance. Returns true the first time only.
function CreatureBrain.kill(c): boolean
	if c.state == "Dead" then
		return false
	end
	c.state = "Dead"
	c.targetKey = nil
	return true
end

return CreatureBrain
