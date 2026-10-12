--[[
	Creates relic specimens. Server only.

	A specimen's ID and traits are generated exactly once, here. The traits table is
	frozen so nothing later (repair, recharge, registration, trading, saving) can change
	it. Randomness and ID generation are passed in so the self-test can be deterministic.

	serialize / deserialize convert a specimen to and from the plain table stored in the
	player's profile. A round trip keeps the ID and every trait.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))

local SpecimenFactory = {}

-- A relic's tier comes from its type (Config.RelicTypes[...].rarity).
function SpecimenFactory.rarityOf(typeId: string): string
	return Config.RelicTypes[typeId].rarity
end

-- Rolls a specimen size: a band by weight (Config.Sizes.Bands), then a size inside it.
function SpecimenFactory.rollSize(rng: Random): number
	local bands = Config.Sizes.Bands
	local total = 0
	for _, band in bands do
		total += band.weight
	end
	local roll = rng:NextNumber() * total
	local chosen = bands[#bands]
	for _, band in bands do
		roll -= band.weight
		if roll < 0 then
			chosen = band
			break
		end
	end
	return math.floor(rng:NextNumber(chosen.min, chosen.max) * 100 + 0.5) / 100
end

local function round(value: number, decimals: number): number
	local m = 10 ^ decimals
	return math.floor(value * m + 0.5) / m
end

-- layer: the Hollow layer the specimen was found in (feeds display income).
function SpecimenFactory.create(
	typeId: string,
	qualityMin: number,
	qualityMax: number,
	rng: Random,
	makeId: () -> string,
	layer: number?
)
	local relicType = Config.RelicTypes[typeId]
	assert(relicType, "Unknown relic type: " .. tostring(typeId))

	-- Higher tiers roll from a better quality band, so their hidden traits are stronger.
	local bonus = Config.RarityById[relicType.rarity].quality
	local quality = math.clamp(rng:NextNumber(qualityMin, qualityMax) + bonus, 0, 1)

	local traits = {}
	for _, def in relicType.traits do
		local t = math.clamp(quality + rng:NextNumber(-Config.TraitSpread, Config.TraitSpread), 0, 1)
		traits[def.id] = round(def.min + (def.max - def.min) * t, def.decimals)
	end

	return {
		id = makeId(),
		typeId = typeId,
		quality = quality, -- hidden; never sent to clients
		rarity = relicType.rarity, -- Delegated: visible on pickup
		traits = table.freeze(traits), -- permanent
		size = SpecimenFactory.rollSize(rng), -- visible; bigger earns more
		layer = layer or 1,

		ownerUserId = nil :: number?,
		location = "World", -- "World" | "Carried" | "Placed"
		slot = nil :: number?, -- display slot while Placed

		-- Three separate states (Decided). None implies another.
		appraised = false,
		activated = not relicType.requiresActivation,
		registered = false,

		-- Usability, restored later by repair/recharge without touching traits.
		condition = 1,
		charge = 1,

		foundAt = nil :: number?,
		registeredAt = nil :: number?,
	}
end

-- Plain table for the profile. Owner, location, and slot are not stored here: the
-- profile key is the owner, and Placed holds slot assignments.
function SpecimenFactory.serialize(specimen)
	return {
		typeId = specimen.typeId,
		quality = specimen.quality,
		rarity = specimen.rarity,
		traits = table.clone(specimen.traits),
		size = specimen.size,
		layer = specimen.layer,
		appraised = specimen.appraised,
		activated = specimen.activated,
		registered = specimen.registered,
		condition = specimen.condition,
		charge = specimen.charge,
		foundAt = specimen.foundAt,
		registeredAt = specimen.registeredAt,
	}
end

-- Returns nil for records whose relic type no longer exists in Config.
function SpecimenFactory.deserialize(id: string, saved)
	if not Config.RelicTypes[saved.typeId] then
		return nil
	end
	return {
		id = id,
		typeId = saved.typeId,
		quality = saved.quality,
		rarity = Config.RelicTypes[saved.typeId].rarity, -- the type's tier (older saves used other labels)
		traits = table.freeze(table.clone(saved.traits)),
		size = saved.size or 1, -- saves from before sizes were added
		layer = saved.layer or 1,
		ownerUserId = nil :: number?,
		location = "Carried",
		slot = nil :: number?,
		appraised = saved.appraised == true,
		activated = saved.activated == true,
		registered = saved.registered == true,
		condition = saved.condition or 1,
		charge = saved.charge or 1,
		foundAt = saved.foundAt,
		registeredAt = saved.registeredAt,
	}
end

return SpecimenFactory
