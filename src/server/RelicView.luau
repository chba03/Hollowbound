--[[
	Builds the data a client is allowed to see about a specimen.
	Traits stay on the server until the specimen is appraised. Appraisal comes in a
	later milestone, so for now they never leave the server. Income uses only type,
	rarity, and layer, which are visible on pickup.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))

local RelicView = {}

function RelicView.forOwner(specimen)
	local relicType = Config.RelicTypes[specimen.typeId]
	local view = {
		id = specimen.id,
		name = Progression.relicName(specimen.typeId, specimen.size),
		size = specimen.size or 1,
		rarity = specimen.rarity,
		layer = specimen.layer,
		security = if specimen.registered then "Registered" else "Unsecured",
		appraisal = if specimen.appraised then "Appraised" else "Unappraised",
		activation = if specimen.activated then "Active" else "Needs activation",
		placed = specimen.location == "Placed",
		income = Progression.incomeOf(specimen),
	}

	if specimen.appraised then
		local traits = {}
		for _, def in relicType.traits do
			table.insert(traits, { label = def.label, value = specimen.traits[def.id], unit = def.unit })
		end
		view.traits = traits
	end

	return view
end

return RelicView
