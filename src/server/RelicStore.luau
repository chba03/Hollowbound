--[[
	Server-memory store of every specimen and every player's relics.

	This module uses no Roblox services so its rules can be self-tested in isolation.
	PlayerData copies registered relics into the saved profile; this store is the live,
	in-memory view during a session.

	Specimen location: "World" (lying in the Hollow), "Carried" (in the owner's pack), or
	"Placed" (on a display pedestal at the owner's plot, with specimen.slot set).

	Concurrency note: Roblox runs server Luau on one thread. A handler cannot be
	interrupted unless it yields. claim() checks and claims without yielding, so when
	two pickup requests arrive together, they run one after the other and only the
	first one succeeds.
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

local function addToInventory(self, userId: number, specimenId: string)
	local inventory = inventoryFor(self, userId)
	if not inventory.has[specimenId] then
		inventory.has[specimenId] = true
		table.insert(inventory.order, specimenId)
	end
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

-- Removes a relic that still lies unclaimed in the world (the night reset).
-- Returns true if it was removed. Never touches owned relics. Must not yield.
function RelicStore:removeWorld(specimenId: string): boolean
	local specimen = self.specimens[specimenId]
	if not specimen or specimen.ownerUserId ~= nil or specimen.location ~= "World" then
		return false
	end
	self.specimens[specimenId] = nil
	return true
end

-- Restores a saved specimen for its owner when they join. Saved specimens are always
-- registered (only registered relics are saved), so they come back secured.
function RelicStore:restore(specimen, userId: number)
	assert(specimen.registered, "Only registered specimens are restored from saves")
	specimen.ownerUserId = userId
	specimen.location = "Carried"
	specimen.slot = nil
	self:add(specimen)
	addToInventory(self, userId, specimen.id)
end

-- Every specimen the player owns (carried and placed), in pickup order.
function RelicStore:owned(userId: number)
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

-- Specimens in the player's pack (not on display), in pickup order.
function RelicStore:carried(userId: number)
	local list = {}
	for _, specimen in self:owned(userId) do
		if specimen.location == "Carried" then
			table.insert(list, specimen)
		end
	end
	return list
end

-- Specimens on display at the player's plot, keyed by slot.
function RelicStore:placed(userId: number)
	local bySlot = {}
	for _, specimen in self:owned(userId) do
		if specimen.location == "Placed" then
			bySlot[specimen.slot] = specimen
		end
	end
	return bySlot
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

-- Puts a carried, registered relic on display slot `slot`. Only registered relics can
-- be displayed, so a display always holds a secured specimen.
-- Returns true, or false plus a reason:
-- "NotFound" | "NotOwner" | "NotCarried" | "Unregistered" | "SlotLocked" | "SlotTaken"
function RelicStore:place(userId: number, specimenId: string, slot: number, capacity: number): (boolean, string?)
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
	if not specimen.registered then
		return false, "Unregistered"
	end
	if slot < 1 or slot > capacity then
		return false, "SlotLocked"
	end
	if self:placed(userId)[slot] then
		return false, "SlotTaken"
	end
	specimen.location = "Placed"
	specimen.slot = slot
	return true
end

-- Takes a displayed relic back into the pack. Returns the specimen, or nil.
function RelicStore:unplace(userId: number, slot: number)
	local specimen = self:placed(userId)[slot]
	if not specimen then
		return nil
	end
	specimen.location = "Carried"
	specimen.slot = nil
	return specimen
end

-- Forgets everything a leaving player owns. Registered relics are already in their
-- save. Open: unregistered relics are forfeited when a player leaves mid-expedition;
-- the design record only defines what happens on final death.
-- Returns the number of unsecured relics that were forfeited.
function RelicStore:releasePlayer(userId: number): number
	local forfeited = 0
	for _, specimen in self:owned(userId) do
		if not specimen.registered then
			forfeited += 1
		end
		self.specimens[specimen.id] = nil
	end
	self.inventories[userId] = nil
	return forfeited
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

return RelicStore
