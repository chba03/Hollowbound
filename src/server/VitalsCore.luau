--[[
	Health and condition of one character. Pure; no Roblox services. Server only.

	condition: "Alive" | "Downed" | "Dead"
	  - Damage through the central interface (Vitals) never kills: reaching 0 health
	    downs the character instead (Decided: a downed stage before final death).
	  - Only the engine's death (bleedout ends it, Reset Character, the void, departure)
	    makes a character Dead, and that goes through the existing final-death path.

	Identifiers make stale callbacks harmless:
	  charId     unique per spawned character (never reused on this server)
	  downToken  increases every time the character is downed; a revive, self-rescue,
	             or bleedout must present the token of the down it belongs to.
]]

local VitalsCore = {}

local function isFinitePositive(value): boolean
	return typeof(value) == "number" and value == value and value > 0 and value ~= math.huge
end

function VitalsCore.new(charId: number, maxHealth: number)
	return {
		charId = charId,
		condition = "Alive",
		health = maxHealth,
		maxHealth = maxHealth,
		downToken = 0,
		downedAt = nil :: number?,
		bleedoutAt = nil :: number?,
		lastDamagedAt = -math.huge,
	}
end

--[[
	Applies damage. Returns "Hurt", "Downed", or "Refused" plus a reason.
	cfg = { healthWhileDowned, bleedoutSeconds }
]]
function VitalsCore.damage(v, amount: any, now: number, cfg): (string, string?)
	if not isFinitePositive(amount) then
		return "Refused", "BadAmount"
	end
	if v.condition ~= "Alive" then
		return "Refused", "NotAlive"
	end
	v.lastDamagedAt = now
	v.health = math.max(0, v.health - amount)
	if v.health > 0 then
		return "Hurt", nil
	end
	v.condition = "Downed"
	v.health = cfg.healthWhileDowned
	v.downToken += 1
	v.downedAt = now
	v.bleedoutAt = now + cfg.bleedoutSeconds
	return "Downed", nil
end

-- Heals an Alive character. Returns the amount actually healed (0 if refused).
function VitalsCore.heal(v, amount: any): number
	if v.condition ~= "Alive" or not isFinitePositive(amount) then
		return 0
	end
	local before = v.health
	v.health = math.min(v.maxHealth, v.health + amount)
	return v.health - before
end

-- Brings a Downed character back. The character id and token must match the current
-- down, so a delayed or duplicate revive can never apply twice, to a later down, or to
-- a new character (whose tokens start again from 0).
function VitalsCore.revive(v, charId: number, token: number, health: number): (boolean, string?)
	if v.charId ~= charId then
		return false, "StaleCharacter"
	end
	if v.condition ~= "Downed" then
		return false, "NotDowned"
	end
	if token ~= v.downToken then
		return false, "StaleToken"
	end
	v.condition = "Alive"
	v.health = math.clamp(health, 1, v.maxHealth)
	v.downedAt = nil
	v.bleedoutAt = nil
	return true, nil
end

-- True when this down has bled out (token must match the current down).
function VitalsCore.bleedoutDue(v, token: number, now: number): boolean
	return v.condition == "Downed" and token == v.downToken and v.bleedoutAt ~= nil and now >= v.bleedoutAt
end

-- Final: the engine killed the character. Returns true the first time only.
function VitalsCore.markDead(v): boolean
	if v.condition == "Dead" then
		return false
	end
	v.condition = "Dead"
	v.health = 0
	v.bleedoutAt = nil
	return true
end

return VitalsCore
