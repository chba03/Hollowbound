--[[
	Builds the data a client is allowed to see about a specimen.
	Traits stay on the server until the specimen is appraised. Appraisal comes in a
	later milestone, so for now they never leave the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))

local RelicView = {}

function RelicView.forOwner(specimen)
	local relicType = Config.RelicTypes[specimen.typeId]
	local view = {
		id = specimen.id,
		name = relicType.displayName,
		rarity = specimen.rarity,
		security = if specimen.registered then "Registered" else "Unsecured",
		appraisal = if specimen.appraised then "Appraised" else "Unappraised",
		activation = if specimen.activated then "Active" else "Needs activation",
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
