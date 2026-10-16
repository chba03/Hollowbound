--[[
	Builds the data a client is allowed to see about its own relics. Server only.

	Never included: quality, other players' relics, and traits of unappraised relics.
	Traits leave the server only after appraisal, and only to the owner.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local LoadoutRules = require(Shared:WaitForChild("LoadoutRules"))
local RelicDefs = require(script.Parent.RelicDefs)

local RelicView = {}

-- Player-facing text for a RelicStore/AbilityRules usability reason.
RelicView.BLOCKERS = {
	NotEquipped = "Not equipped",
	NeedsActivation = "Needs town activation",
	NeedsService = "Needs service in town",
	NoCharges = "No charges: recharge in town",
	NoAbility = "No ability yet",
}

function RelicView.forOwner(store, userId: number, specimen)
	local relicType = Config.RelicTypes[specimen.typeId]
	local abilityId, ability = RelicDefs.ability(specimen.typeId)
	local requiresActivation = RelicDefs.requiresActivation(specimen.typeId)
	local slot = store:slotOf(userId, specimen.id)

	local activation
	if not requiresActivation then
		activation = "Works immediately"
	elseif specimen.activated then
		activation = "Activated"
	else
		activation = "Needs activation"
	end

	local blocker = ""
	if not ability then
		blocker = RelicView.BLOCKERS.NoAbility
	else
		local ok, reason = store:checkUsable(userId, specimen.id, requiresActivation)
		if not ok and reason ~= "NotEquipped" then
			blocker = RelicView.BLOCKERS[reason] or reason
		end
	end

	local view = {
		id = specimen.id,
		typeId = specimen.typeId,
		name = relicType.displayName,
		rarity = specimen.rarity,
		slotClass = LoadoutRules.classOfRarity(specimen.rarity) or "",
		security = if specimen.registered then "Registered" else "Unsecured",
		appraisal = if specimen.appraised then "Appraised" else "Unappraised",
		activation = activation,
		needsActivation = requiresActivation and not specimen.activated,
		service = if specimen.needsService then "Needs service" else "Good condition",
		charges = specimen.charges or 0,
		maxCharges = RelicDefs.maxCharges(specimen.typeId),
		equippedSlot = slot or 0,
		blocker = blocker,
		abilityId = abilityId or "",
		abilityName = if ability then ability.displayName else "",
		abilityText = if ability then ability.description else "",
	}

	if specimen.appraised then
		local traits = {}
		for _, def in relicType.traits do
			local value = specimen.traits[def.id]
			if value ~= nil then
				table.insert(traits, { label = def.label, value = value, unit = def.unit })
			end
		end
		view.traits = traits
	end

	return view
end

--[[
	Everything the HUD needs:
	{ relics = { view }, slots = { specimenId or "" } (length = slot count),
	  cooldowns = { [abilityId] = seconds left }, save = { mode, state, text },
	  atDesk = boolean, maxPerClass = { [class] = number } }
]]
function RelicView.state(store, sessions, player: Player, atDesk: boolean)
	local userId = player.UserId
	local relics = {}
	for _, specimen in store:carried(userId) do
		table.insert(relics, RelicView.forOwner(store, userId, specimen))
	end
	local slots = {}
	for slot = 1, LoadoutRules.slots do
		slots[slot] = store:equippedIn(userId, slot) or ""
	end
	return {
		relics = relics,
		slots = slots,
		cooldowns = sessions:cooldownsRemaining(userId),
		save = sessions:status(userId),
		atDesk = atDesk,
		maxPerClass = LoadoutRules.maxPerClass,
	}
end

return RelicView
