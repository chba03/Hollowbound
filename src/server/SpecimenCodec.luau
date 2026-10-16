--[[
	Converts live specimens to saved records and back. Server only.

	Loading never generates anything: ID, type, rarity, quality, and traits come only
	from the saved record. Fields added in later versions get deterministic defaults
	(the same record always decodes to the same specimen). A record that fails
	validation is returned as an error so Sessions can keep it untouched in the profile
	(quarantine) instead of deleting it.

	Record format v1 (string keys only, ProfileStore-safe):
	  { v = 1, id, ownerUserId, typeId, rarity, quality, traits = { [traitId] = number },
	    registered = true, appraised, activated, needsService, condition, charges,
	    foundAt?, registeredAt?, servicedAt?, appraisedAt?, activatedAt? }
]]

local RelicDefs = require(script.Parent.RelicDefs)

local SpecimenCodec = {}

SpecimenCodec.RecordVersion = 1

local OPTIONAL_TIMES = { "foundAt", "registeredAt", "servicedAt", "appraisedAt", "activatedAt" }

function SpecimenCodec.encode(specimen)
	local traits = {}
	for key, value in specimen.traits do
		traits[key] = value
	end
	local record = {
		v = SpecimenCodec.RecordVersion,
		id = specimen.id,
		ownerUserId = specimen.ownerUserId,
		typeId = specimen.typeId,
		rarity = specimen.rarity,
		quality = specimen.quality,
		traits = traits,
		registered = specimen.registered == true,
		appraised = specimen.appraised == true,
		activated = specimen.activated == true,
		needsService = specimen.needsService == true,
		condition = specimen.condition,
		charges = specimen.charges,
	}
	for _, key in OPTIONAL_TIMES do
		if typeof(specimen[key]) == "number" then
			record[key] = specimen[key]
		end
	end
	return record
end

local function isFiniteNumber(value): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Returns (specimen, nil) or (nil, reason). key is the record's key in Relics.
function SpecimenCodec.decode(key: string, record, expectedUserId: number)
	if typeof(record) ~= "table" then
		return nil, "record is not a table"
	end
	if typeof(record.v) == "number" and record.v > SpecimenCodec.RecordVersion then
		return nil, "record version is newer than this server"
	end
	if typeof(record.id) ~= "string" or record.id ~= key then
		return nil, "id does not match its key"
	end
	if record.ownerUserId ~= expectedUserId then
		return nil, "owner does not match this profile"
	end
	if record.registered ~= true then
		return nil, "record is not registered"
	end
	if typeof(record.typeId) ~= "string" or RelicDefs.type(record.typeId) == nil then
		return nil, "unknown relic type " .. tostring(record.typeId)
	end
	if typeof(record.rarity) ~= "string" then
		return nil, "missing rarity"
	end
	if typeof(record.traits) ~= "table" then
		return nil, "missing traits"
	end
	local traits = {}
	for traitId, value in record.traits do
		if typeof(traitId) ~= "string" or not isFiniteNumber(value) then
			return nil, "invalid trait " .. tostring(traitId)
		end
		traits[traitId] = value
	end

	-- Deterministic defaults for fields a record may lack.
	local maxCharges = RelicDefs.maxCharges(record.typeId)
	local charges
	if isFiniteNumber(record.charges) then
		charges = math.clamp(math.floor(record.charges), 0, maxCharges)
	elseif isFiniteNumber(record.charge) then
		-- Earlier in-memory field: a 0..1 fraction of a full charge.
		charges = math.clamp(math.floor(record.charge * maxCharges + 0.5), 0, maxCharges)
	else
		charges = maxCharges
	end
	local activated = record.activated
	if typeof(activated) ~= "boolean" then
		activated = not RelicDefs.requiresActivation(record.typeId)
	end

	local specimen = {
		id = record.id,
		typeId = record.typeId,
		quality = if isFiniteNumber(record.quality) then record.quality else 0,
		rarity = record.rarity,
		traits = table.freeze(traits),
		ownerUserId = expectedUserId,
		location = "Carried",
		appraised = record.appraised == true,
		activated = activated,
		registered = true,
		needsService = record.needsService == true,
		condition = if isFiniteNumber(record.condition) then math.clamp(record.condition, 0, 1) else 1,
		charges = charges,
	}
	for _, timeKey in OPTIONAL_TIMES do
		if isFiniteNumber(record[timeKey]) then
			specimen[timeKey] = record[timeKey]
		end
	end
	return specimen, nil
end

return SpecimenCodec
