--[[
	Creates relic specimens. Server only.

	A specimen's ID and traits are generated exactly once, here. The traits table is
	frozen so nothing later (repair, recharge, registration, trading) can change it.
	Randomness and ID generation are passed in so the self-test can be deterministic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local RelicDefs = require(script.Parent.RelicDefs)

local SpecimenFactory = {}

function SpecimenFactory.rarityForQuality(quality: number): string
	local result = Config.Rarities[1].id
	for _, tier in Config.Rarities do
		if quality >= tier.minQuality then
			result = tier.id
		end
	end
	return result
end

local function round(value: number, decimals: number): number
	local m = 10 ^ decimals
	return math.floor(value * m + 0.5) / m
end

function SpecimenFactory.create(typeId: string, qualityMin: number, qualityMax: number, rng: Random, makeId: () -> string)
	local relicType = Config.RelicTypes[typeId]
	assert(relicType, "Unknown relic type: " .. tostring(typeId))

	local quality = rng:NextNumber(qualityMin, qualityMax)

	local traits = {}
	for _, def in relicType.traits do
		local t = math.clamp(quality + rng:NextNumber(-Config.TraitSpread, Config.TraitSpread), 0, 1)
		traits[def.id] = round(def.min + (def.max - def.min) * t, def.decimals)
	end

	return {
		id = makeId(),
		typeId = typeId,
		quality = quality, -- hidden; never sent to clients
		rarity = SpecimenFactory.rarityForQuality(quality), -- Delegated: visible on pickup
		traits = table.freeze(traits), -- permanent

		ownerUserId = nil :: number?,
		location = "World", -- "World" (lying in the expedition) or "Carried"

		-- Separate states (Decided). None implies another.
		appraised = false,
		activated = not relicType.requiresActivation,
		registered = false,
		needsService = false, -- set when a registered relic returns after final death

		-- Usability, restored by town service (repair/recharge) without touching traits.
		condition = 1,
		charges = RelicDefs.maxCharges(typeId), -- ability uses left; 0 if the type has no ability

		foundAt = nil :: number?,
		registeredAt = nil :: number?,
		servicedAt = nil :: number?,
		appraisedAt = nil :: number?,
		activatedAt = nil :: number?,
	}
end

return SpecimenFactory
