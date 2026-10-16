-- Read-only lookups over Config.RelicTypes and Config.Abilities, so callers do not
-- repeat nil checks or string keys.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))

local RelicDefs = {}

function RelicDefs.type(typeId: string)
	return Config.RelicTypes[typeId]
end

function RelicDefs.displayName(typeId: string): string
	local relicType = Config.RelicTypes[typeId]
	return if relicType then relicType.displayName else typeId
end

function RelicDefs.requiresActivation(typeId: string): boolean
	local relicType = Config.RelicTypes[typeId]
	return relicType ~= nil and relicType.requiresActivation == true
end

-- (abilityId, abilityDef) or nil if the type has no ability.
function RelicDefs.ability(typeId: string)
	local relicType = Config.RelicTypes[typeId]
	local abilityId = relicType and relicType.ability
	if abilityId and Config.Abilities[abilityId] then
		return abilityId, Config.Abilities[abilityId]
	end
	return nil, nil
end

function RelicDefs.maxCharges(typeId: string): number
	local _, ability = RelicDefs.ability(typeId)
	return if ability then ability.maxCharges else 0
end

-- The trait definition for a type, or nil.
function RelicDefs.traitDef(typeId: string, traitId: string)
	local relicType = Config.RelicTypes[typeId]
	if not relicType then
		return nil
	end
	for _, def in relicType.traits do
		if def.id == traitId then
			return def
		end
	end
	return nil
end

return RelicDefs
