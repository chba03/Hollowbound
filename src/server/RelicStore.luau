--[[
	Server-memory store of every specimen, every player's carried relics, and every
	player's equipped loadout. This is the live, authoritative state; Sessions copies the
	registered part of it into the player's saved profile.

	This module uses no Roblox services so its rules can be tested in isolation.

	Concurrency note: Roblox runs server Luau on one thread. A handler cannot be
	interrupted unless it yields. No method here yields, so each check-then-change runs
	as one step: when two pickups of the same relic arrive together, the first claim
	wins and the second sees it owned. Storage calls (which do yield) happen elsewhere
	and never between a check and its change.

	Reasons returned on failure are short ids; RelicActions turns them into messages.
]]

local RelicStore = {}
RelicStore.__index = RelicStore

function RelicStore.new(clock: (() -> number)?)
	return setmetatable({
		specimens = {}, -- [specimenId] = specimen
		inventories = {}, -- [userId] = { order = { specimenId }, has = { [specimenId] = true } }
		loadouts = {}, -- [userId] = { [slot] = specimenId }
		clock = clock or os.time,
	}, RelicStore)
end

function RelicStore:add(specimen)
	assert(self.specimens[specimen.id] == nil, "Duplicate specimen id " .. tostring(specimen.id))
	self.specimens[specimen.id] = specimen
end

function RelicStore:get(specimenId: string)
	return self.specimens[specimenId]
end

local function inventoryFor(self, userId: number)
	local inventory = self.inventories[userId]
	if not inventory then
		inventory = { order = {}, has = {} }
		self.inventories[userId] = inventory
	end
	return inventory
end

local function loadoutFor(self, userId: number)
	local loadout = self.loadouts[userId]
	if not loadout then
		loadout = {}
		self.loadouts[userId] = loadout
	end
	return loadout
end

local function addToInventory(self, userId: number, specimenId: string)
	local inventory = inventoryFor(self, userId)
	if not inventory.has[specimenId] then
		inventory.has[specimenId] = true
		table.insert(inventory.order, specimenId)
	end
end

local function removeFromInventory(self, userId: number, specimenId: string)
	local inventory = self.inventories[userId]
	if not inventory or not inventory.has[specimenId] then
		return
	end
	inventory.has[specimenId] = nil
	local index = table.find(inventory.order, specimenId)
	if index then
		table.remove(inventory.order, index)
	end
end

-- Removes a specimen from any slot of the player's loadout. Returns true if it was equipped.
local function unequipSpecimen(self, userId: number, specimenId: string): boolean
	local loadout = self.loadouts[userId]
	if not loadout then
		return false
	end
	for slot, id in loadout do
		if id == specimenId then
			loadout[slot] = nil
			return true
		end
	end
	return false
end

-- Common ownership check: the specimen exists, belongs to userId, and is carried.
local function owned(self, userId: number, specimenId: any)
	if typeof(specimenId) ~= "string" then
		return nil, "NotFound"
	end
	local specimen = self.specimens[specimenId]
	if not specimen then
		return nil, "NotFound"
	end
	if specimen.ownerUserId ~= userId then
		return nil, "NotOwner"
	end
	if specimen.location ~= "Carried" then
		return nil, "NotCarried"
	end
	return specimen, nil
end

-- Pickup establishes ownership (Decided). Must not yield.
-- Returns true, or false plus a reason: "NotFound" | "AlreadyOwned" | "Unavailable".
function RelicStore:claim(specimenId: string, userId: number): (boolean, string?)
	local specimen = self.specimens[specimenId]
	if not specimen then
		return false, "NotFound"
	end
	if specimen.ownerUserId ~= nil then
		return false, "AlreadyOwned"
	end
	if specimen.location ~= "World" then
		return false, "Unavailable"
	end

	specimen.ownerUserId = userId
	specimen.location = "Carried"
	specimen.foundAt = self.clock()
	addToInventory(self, userId, specimenId)
	return true
end

-- Puts a specimen loaded from the player's saved profile back into memory, exactly as
-- saved. It is never regenerated. Refuses if any specimen with that ID is already live.
function RelicStore:restore(userId: number, specimen): (boolean, string?)
	if self.specimens[specimen.id] ~= nil then
		return false, "AlreadyLive"
	end
	specimen.ownerUserId = userId
	specimen.location = "Carried"
	self.specimens[specimen.id] = specimen
	addToInventory(self, userId, specimen.id)
	return true
end

-- Specimens the player carries, in pickup order.
function RelicStore:carried(userId: number)
	local list = {}
	local inventory = self.inventories[userId]
	if not inventory then
		return list
	end
	for _, specimenId in inventory.order do
		local specimen = self.specimens[specimenId]
		if specimen and specimen.ownerUserId == userId then
			table.insert(list, specimen)
		end
	end
	return list
end

-- Registers every carried relic that is not yet registered. Changes the existing
-- records in place: no copies, new IDs, trait changes, charge refills, or service.
-- Returns (newlyRegistered, alreadyRegistered) as lists of specimens.
function RelicStore:registerCarried(userId: number)
	local newly, already = {}, {}
	for _, specimen in self:carried(userId) do
		if specimen.registered then
			table.insert(already, specimen)
		else
			specimen.registered = true
			specimen.registeredAt = self.clock()
			table.insert(newly, specimen)
		end
	end
	return newly, already
end

-- Appraisal reveals existing traits to the owner (Delegated). It changes nothing else.
function RelicStore:appraise(userId: number, specimenId: any): (boolean, string?)
	local specimen, reason = owned(self, userId, specimenId)
	if not specimen then
		return false, reason
	end
	if specimen.appraised then
		return false, "AlreadyAppraised"
	end
	specimen.appraised = true
	specimen.appraisedAt = self.clock()
	return true
end

-- Activation enables use for types that require it (Decided). It changes nothing else.
function RelicStore:activate(userId: number, specimenId: any, requiresActivation: boolean): (boolean, string?)
	local specimen, reason = owned(self, userId, specimenId)
	if not specimen then
		return false, reason
	end
	if not requiresActivation then
		return false, "ActivationNotRequired"
	end
	if specimen.activated then
		return false, "AlreadyActivated"
	end
	specimen.activated = true
	specimen.activatedAt = self.clock()
	return true
end

--[[
	Loadout. rules = {
		slots = number,
		classOf = function(specimen) -> string?,   -- nil means not equippable
		maxPerClass = { [class] = number },        -- classes without an entry are unlimited
	}
]]

-- Copy of the player's loadout: { [slot] = specimenId }.
function RelicStore:loadout(userId: number)
	local copy = {}
	for slot, id in self.loadouts[userId] or {} do
		copy[slot] = id
	end
	return copy
end

function RelicStore:slotOf(userId: number, specimenId: string): number?
	for slot, id in self.loadouts[userId] or {} do
		if id == specimenId then
			return slot
		end
	end
	return nil
end

function RelicStore:equippedIn(userId: number, slot: number): string?
	local loadout = self.loadouts[userId]
	return loadout and loadout[slot]
end

-- Equips a carried specimen into a slot, replacing whatever was there.
-- Returns (true, nil, replacedId?) or (false, reason).
-- Reasons: BadSlot, NotFound, NotOwner, NotCarried, AlreadyEquipped, NotEquippable, ClassLimit.
function RelicStore:equip(userId: number, specimenId: any, slot: any, rules): (boolean, string?, string?)
	if typeof(slot) ~= "number" or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > rules.slots then
		return false, "BadSlot"
	end
	local specimen, reason = owned(self, userId, specimenId)
	if not specimen then
		return false, reason
	end
	if self:slotOf(userId, specimen.id) ~= nil then
		return false, "AlreadyEquipped"
	end
	local class = rules.classOf(specimen)
	if not class then
		return false, "NotEquippable"
	end

	local loadout = loadoutFor(self, userId)
	local limit = rules.maxPerClass[class]
	if limit then
		local count = 0
		for otherSlot, id in loadout do
			local other = self.specimens[id]
			if otherSlot ~= slot and other and rules.classOf(other) == class then
				count += 1
			end
		end
		if count >= limit then
			return false, "ClassLimit"
		end
	end

	local replaced = loadout[slot]
	loadout[slot] = specimen.id
	return true, nil, replaced
end

-- Returns (true, nil, removedId) or (false, "BadSlot" | "SlotEmpty").
function RelicStore:unequip(userId: number, slot: any, rules): (boolean, string?, string?)
	if typeof(slot) ~= "number" or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > rules.slots then
		return false, "BadSlot"
	end
	local loadout = self.loadouts[userId]
	local removed = loadout and loadout[slot]
	if not removed then
		return false, "SlotEmpty"
	end
	loadout[slot] = nil
	return true, nil, removed
end

-- Whether an equipped relic can be used right now, ignoring cooldowns (those live in
-- the player's session). Reasons: NotFound, NotOwner, NotCarried, NotEquipped,
-- NeedsActivation, NeedsService, NoCharges.
function RelicStore:checkUsable(userId: number, specimenId: any, requiresActivation: boolean): (boolean, string?)
	local specimen, reason = owned(self, userId, specimenId)
	if not specimen then
		return false, reason
	end
	if self:slotOf(userId, specimen.id) == nil then
		return false, "NotEquipped"
	end
	if requiresActivation and not specimen.activated then
		return false, "NeedsActivation"
	end
	if specimen.needsService then
		return false, "NeedsService"
	end
	if (specimen.charges or 0) <= 0 then
		return false, "NoCharges"
	end
	return true
end

-- Spends one charge. Call only after checkUsable succeeded in the same step.
function RelicStore:consumeCharge(userId: number, specimenId: string): boolean
	local specimen = owned(self, userId, specimenId)
	if not specimen or (specimen.charges or 0) <= 0 then
		return false
	end
	specimen.charges -= 1
	return true
end

-- Final death (Decided). Must not yield.
--   Unregistered relics leave the inventory and loadout and return to the world with no
--   owner, so anyone, including the previous owner, can claim them. All their states
--   (appraisal, activation, charges) stay.
--   Registered relics stay owned, carried, and equipped, and are marked Needs service.
-- Calling it again changes nothing new.
-- Returns (dropped, protected, unequippedIds).
function RelicStore:processDeath(userId: number, condition: number, charges: number)
	local dropped, protected, unequipped = {}, {}, {}
	for _, specimen in self:carried(userId) do
		if specimen.registered then
			specimen.needsService = true
			specimen.condition = condition
			specimen.charges = math.min(specimen.charges or 0, charges)
			table.insert(protected, specimen)
		else
			if unequipSpecimen(self, userId, specimen.id) then
				table.insert(unequipped, specimen.id)
			end
			specimen.ownerUserId = nil
			specimen.location = "World"
			removeFromInventory(self, userId, specimen.id)
			table.insert(dropped, specimen)
		end
	end
	return dropped, protected, unequipped
end

-- Temporary departure rule (town departure, lost session): unregistered relics cannot
-- be saved, so they return to the world unchanged. Registered relics are untouched.
-- Returns (released, unequippedIds).
function RelicStore:releaseUnregistered(userId: number)
	local released, unequipped = {}, {}
	for _, specimen in self:carried(userId) do
		if not specimen.registered then
			if unequipSpecimen(self, userId, specimen.id) then
				table.insert(unequipped, specimen.id)
			end
			specimen.ownerUserId = nil
			specimen.location = "World"
			removeFromInventory(self, userId, specimen.id)
			table.insert(released, specimen)
		end
	end
	return released, unequipped
end

-- Removes everything the player still carries from this server's memory, plus their
-- loadout. Used after their registered relics were written to their profile (or after
-- the profile moved to another server). Returns the removed specimens.
function RelicStore:forget(userId: number)
	local removed = self:carried(userId)
	for _, specimen in removed do
		self.specimens[specimen.id] = nil
	end
	self.inventories[userId] = nil
	self.loadouts[userId] = nil
	return removed
end

-- Repair and recharge one specimen (Decided: restores usability, never traits).
-- Clears Needs service, restores condition, and refills charges. Must not yield.
-- Reasons: NotFound, NotOwner, NotCarried, NotNeeded.
function RelicStore:service(userId: number, specimenId: any, condition: number, maxCharges: number): (boolean, string?)
	local specimen, reason = owned(self, userId, specimenId)
	if not specimen then
		return false, reason
	end
	if not specimen.needsService and (specimen.condition or 0) >= condition and (specimen.charges or 0) >= maxCharges then
		return false, "NotNeeded"
	end
	specimen.needsService = false
	specimen.condition = condition
	specimen.charges = maxCharges
	specimen.servicedAt = self.clock()
	return true
end

-- Stable string of a specimen's identity: ID, type, and every permanent trait.
function RelicStore.fingerprint(specimen): string
	local keys = {}
	for key in specimen.traits do
		table.insert(keys, key)
	end
	table.sort(keys)
	local parts = { specimen.id, specimen.typeId, specimen.rarity }
	for _, key in keys do
		table.insert(parts, `{key}={specimen.traits[key]}`)
	end
	return table.concat(parts, "|")
end

-- Identity plus the states that death, recovery, and service must never change.
function RelicStore.identityAndStates(specimen): string
	return `{RelicStore.fingerprint(specimen)}|registered={specimen.registered}|appraised={specimen.appraised}|activated={specimen.activated}`
end

return RelicStore
