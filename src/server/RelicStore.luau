--[[
	Server-memory store of every specimen and every player's carried relics.

	This module uses no Roblox services so its rules can be self-tested in isolation.
	Everything is kept in memory: data is lost when the server shuts down.
	Saving between sessions comes in a later milestone.

	Concurrency note: Roblox runs server Luau on one thread. A handler cannot be
	interrupted unless it yields. claim() checks and claims without yielding, so when
	two pickup requests arrive together, they run one after the other and only the
	first one succeeds. processDeath() and service() also never yield.
]]

local RelicStore = {}
RelicStore.__index = RelicStore

function RelicStore.new(clock: (() -> number)?)
	return setmetatable({
		specimens = {}, -- [specimenId] = specimen
		inventories = {}, -- [userId] = { order = { specimenId }, has = { [specimenId] = true } }
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

	local inventory = inventoryFor(self, userId)
	if not inventory.has[specimenId] then
		inventory.has[specimenId] = true
		table.insert(inventory.order, specimenId)
	end
	return true
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
-- records in place: no copies, new IDs, or trait changes.
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

-- Final death (Decided). Must not yield.
--   Unregistered relics leave the inventory and return to the world with no owner, so
--   anyone, including the previous owner, can claim them. Appraisal and activation stay.
--   Registered relics stay owned and carried and are marked as needing service.
-- Calling it again changes nothing: the unregistered relics are already gone, and the
-- protected ones are already marked.
-- Returns (dropped, protected) as lists of specimens.
function RelicStore:processDeath(userId: number, condition: number, charge: number)
	local dropped, protected = {}, {}
	for _, specimen in self:carried(userId) do
		if specimen.registered then
			specimen.needsService = true
			specimen.condition = condition
			specimen.charge = charge
			table.insert(protected, specimen)
		else
			specimen.ownerUserId = nil
			specimen.location = "World"
			removeFromInventory(self, userId, specimen.id)
			table.insert(dropped, specimen)
		end
	end
	return dropped, protected
end

-- Repair/recharge one specimen (Decided: restores usability, never traits).
-- Must not yield. Returns true, or false plus a reason:
-- "NotFound" | "NotOwner" | "NotCarried" | "NotNeeded".
function RelicStore:service(userId: number, specimenId: string, condition: number, charge: number): (boolean, string?)
	local specimen = self.specimens[specimenId]
	if not specimen then
		return false, "NotFound"
	end
	if specimen.ownerUserId ~= userId then
		return false, "NotOwner"
	end
	if specimen.location ~= "Carried" then
		return false, "NotCarried"
	end
	if not specimen.needsService then
		return false, "NotNeeded"
	end
	specimen.needsService = false
	specimen.condition = condition
	specimen.charge = charge
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
	local parts = { specimen.id, specimen.typeId }
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
