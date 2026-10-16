--[[
	Loadout eligibility from Config. Pure; used by the server store (authoritative) and
	by the client only to label buttons.
]]

local Config = require(script.Parent.Config)

local LoadoutRules = {}

LoadoutRules.slots = Config.Loadout.Slots
LoadoutRules.maxPerClass = Config.Loadout.MaxPerClass

-- Slot class for a rarity id, or nil if the rarity is not equippable.
function LoadoutRules.classOfRarity(rarity: string): string?
	return Config.Loadout.ClassByRarity[rarity]
end

-- The rules table RelicStore:equip expects.
function LoadoutRules.forStore()
	return {
		slots = Config.Loadout.Slots,
		maxPerClass = Config.Loadout.MaxPerClass,
		classOf = function(specimen)
			return Config.Loadout.ClassByRarity[specimen.rarity]
		end,
	}
end

return LoadoutRules
