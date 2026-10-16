--[[
	Ordinary items (weapon, bandages, self-rescue kits) and their world drops. Pure; no
	Roblox services. Server only.

	Ordinary items are separate from relics: they are never registered, protected, or
	saved (session-only in this prototype), and final death drops all of them.
	Capacity: an item never exceeds its maxCarry. The free town refill tops each item up
	to townRefill (also capped), so repeated refills cannot exceed those limits.

	Drops: each drop has a unique id and authoritative quantities. claimDrop moves only
	what fits; anything left stays in the same drop. A claim never yields, so competing
	pickups are applied one after the other and items are never duplicated.
]]

local GearStore = {}
GearStore.__index = GearStore

-- defs: Config.Items; order: Config.ItemOrder
function GearStore.new(defs, order)
	return setmetatable({
		defs = defs,
		order = order,
		carried = {}, -- [userId] = { [itemId] = count }
		drops = {}, -- [dropId] = { items = { [itemId] = count } }
		dropCounter = 0,
	}, GearStore)
end

local function bagFor(self, userId: number)
	local bag = self.carried[userId]
	if not bag then
		bag = {}
		self.carried[userId] = bag
	end
	return bag
end

function GearStore:count(userId: number, itemId: string): number
	local bag = self.carried[userId]
	return bag and bag[itemId] or 0
end

-- Copy of everything the player carries: { [itemId] = count } (zero counts omitted).
function GearStore:contents(userId: number)
	local copy = {}
	for itemId, count in self.carried[userId] or {} do
		if count > 0 then
			copy[itemId] = count
		end
	end
	return copy
end

-- The weapon the player carries, if any (first in item order).
function GearStore:weapon(userId: number): string?
	for _, itemId in self.order do
		local def = self.defs[itemId]
		if def and def.kind == "Weapon" and self:count(userId, itemId) > 0 then
			return itemId
		end
	end
	return nil
end

-- Adds up to `amount`, limited by capacity. Returns how many were added.
function GearStore:add(userId: number, itemId: string, amount: number): number
	local def = self.defs[itemId]
	if not def or typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0
	end
	local bag = bagFor(self, userId)
	local current = bag[itemId] or 0
	local added = math.max(0, math.min(math.floor(amount), def.maxCarry - current))
	bag[itemId] = current + added
	return added
end

-- Removes exactly `amount` if available. Returns true on success.
function GearStore:consume(userId: number, itemId: string, amount: number): boolean
	local bag = self.carried[userId]
	local current = bag and bag[itemId] or 0
	if typeof(amount) ~= "number" or amount <= 0 or current < amount then
		return false
	end
	bag[itemId] = current - amount
	return true
end

-- Free town refill: tops every item up to min(townRefill, maxCarry). Items already
-- above that (picked up loot) are kept. Returns { [itemId] = added }.
function GearStore:refill(userId: number)
	local added = {}
	local bag = bagFor(self, userId)
	for _, itemId in self.order do
		local def = self.defs[itemId]
		local target = math.min(def.townRefill or 0, def.maxCarry)
		local current = bag[itemId] or 0
		if current < target then
			bag[itemId] = target
			added[itemId] = target - current
		end
	end
	return added
end

-- Removes everything the player carries. Returns { [itemId] = count }.
function GearStore:takeAll(userId: number)
	local taken = self:contents(userId)
	self.carried[userId] = nil
	return taken
end

-- Creates a drop from item counts. Returns its unique id, or nil if empty.
function GearStore:createDrop(items): string?
	local copy, any = {}, false
	for itemId, count in items do
		if self.defs[itemId] and count > 0 then
			copy[itemId] = count
			any = true
		end
	end
	if not any then
		return nil
	end
	self.dropCounter += 1
	local dropId = `loot-{self.dropCounter}`
	self.drops[dropId] = { items = copy }
	return dropId
end

function GearStore:dropContents(dropId: string)
	local drop = self.drops[dropId]
	if not drop then
		return nil
	end
	local copy = {}
	for itemId, count in drop.items do
		copy[itemId] = count
	end
	return copy
end

-- Moves what fits from a drop into the player's items. Must not yield.
-- Returns (taken, emptied) or (nil, reason): "Gone" | "NoRoom".
function GearStore:claimDrop(dropId: any, userId: number)
	local drop = typeof(dropId) == "string" and self.drops[dropId]
	if not drop then
		return nil, "Gone"
	end
	local taken, any = {}, false
	for itemId, count in drop.items do
		local added = self:add(userId, itemId, count)
		if added > 0 then
			taken[itemId] = added
			drop.items[itemId] = count - added
			any = true
		end
		if drop.items[itemId] <= 0 then
			drop.items[itemId] = nil
		end
	end
	if not any then
		return nil, "NoRoom"
	end
	local emptied = next(drop.items) == nil
	if emptied then
		self.drops[dropId] = nil
	end
	return taken, emptied
end

function GearStore:removeDrop(dropId: string)
	self.drops[dropId] = nil
end

return GearStore
