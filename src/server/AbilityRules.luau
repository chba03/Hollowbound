--[[
	Ability rules without side effects in the world. Server only.

	tryUse checks everything except the character's life state (Abilities checks that,
	because it needs the live character), then spends a charge and starts the cooldown,
	all in one non-yielding step. Effects are applied afterwards by Abilities.

	Tuned values come from Config.Abilities. A { trait, worst, best } entry maps the
	specimen's existing trait (normalized within its type's min..max) onto worst..best.
	A missing trait uses worst: older specimens keep their traits and are never rerolled.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LoadoutRules = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("LoadoutRules"))
local RelicDefs = require(script.Parent.RelicDefs)

local AbilityRules = {}

-- Resolves one tuned value for a specimen.
function AbilityRules.tuned(specimen, value): number
	if typeof(value) == "number" then
		return value
	end
	local def = RelicDefs.traitDef(specimen.typeId, value.trait)
	local raw = specimen.traits[value.trait]
	local t = 0
	if def and typeof(raw) == "number" and def.max > def.min then
		t = math.clamp((raw - def.min) / (def.max - def.min), 0, 1)
	end
	return value.worst + (value.best - value.worst) * t
end

-- Ability parameters for a specimen, with server caps applied.
function AbilityRules.params(specimen)
	local abilityId, ability = RelicDefs.ability(specimen.typeId)
	if not ability then
		return nil
	end
	local params = {
		abilityId = abilityId,
		cooldown = AbilityRules.tuned(specimen, ability.cooldown),
	}
	if abilityId == "Windhook" then
		params.duration = ability.duration
		params.forwardSpeed = math.min(AbilityRules.tuned(specimen, ability.forwardSpeed), ability.maxForwardSpeed)
		params.upwardSpeed = math.min(AbilityRules.tuned(specimen, ability.upwardSpeed), ability.maxUpwardSpeed)
		params.maxForce = ability.maxForce
	elseif abilityId == "EchoLens" then
		params.radius = AbilityRules.tuned(specimen, ability.radius)
		params.markDuration = AbilityRules.tuned(specimen, ability.markDuration)
		params.maxTargets = ability.maxTargets
	end
	return params
end

--[[
	Validates and pays for one use of the relic in `slot`.
	cooldowns: { getDeadline = (abilityId) -> number?, setDeadline = (abilityId, number) -> () }
	Returns (true, nil, specimen, params) or (false, reason).
	Reasons: BadSlot, SlotEmpty, NoAbility, CoolingDown, plus RelicStore:checkUsable reasons.
]]
function AbilityRules.tryUse(store, cooldowns, userId: number, slot: any, now: number)
	if typeof(slot) ~= "number" or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > LoadoutRules.slots then
		return false, "BadSlot"
	end
	local specimenId = store:equippedIn(userId, slot)
	if not specimenId then
		return false, "SlotEmpty"
	end
	local specimen = store:get(specimenId)
	if not specimen then
		return false, "NotFound"
	end
	local params = AbilityRules.params(specimen)
	if not params then
		return false, "NoAbility"
	end
	local ok, reason = store:checkUsable(userId, specimenId, RelicDefs.requiresActivation(specimen.typeId))
	if not ok then
		return false, reason
	end
	local deadline = cooldowns.getDeadline(params.abilityId)
	if deadline and now < deadline then
		return false, "CoolingDown", nil, nil, deadline - now
	end
	store:consumeCharge(userId, specimenId)
	cooldowns.setDeadline(params.abilityId, now + params.cooldown)
	return true, nil, specimen, params
end

return AbilityRules
