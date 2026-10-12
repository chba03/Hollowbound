--[[
	Server-memory store of every specimen and every player's carried relics.

	This module uses no Roblox services so its rules can be self-tested in isolation.
	Milestone 1 keeps everything in memory: data is lost when the server shuts down.

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
