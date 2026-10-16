--[[
	Per-player saved sessions. Server only. Works with any backend that implements the
	interface described in ProfileBackend (the real one, or MockBackend in tests).

	Saved data (one profile per UserId, key Config.Persistence.KeyPrefix .. userId):
	  SchemaVersion  number
	  Revision       number, +1 on every commit
	  Relics         { [specimenId] = SpecimenCodec record }   registered relics only
	  Loadout        { ["1".."N"] = specimenId }                registered relics only
	  Cooldowns      { [abilityId] = unix time the cooldown ends }

	Rules this module enforces:
	  - Gameplay mutations are refused until the profile has loaded (canMutate), and
	    again if the session is lost. A failed load reports an error; nothing is created
	    in its place, and the stored data is not modified.
	  - Loading never regenerates a specimen: records are decoded by SpecimenCodec.
	    Records that fail to decode stay in the profile untouched (quarantine).
	  - commit() writes a full snapshot of the player's registered relics, loadout, and
	    cooldowns into the profile in one non-yielding step, then bumps Revision. Saves
	    therefore always contain a consistent, latest state. Storage calls that yield
	    happen inside the backend, never between a store check and its change.
	  - A commit never removes a relic that is already in the profile (anti-wipe guard):
	    in this milestone registered relics cannot legitimately leave a profile.
	  - Save confirmation is monotonic: confirmedRevision only grows, so a late or
	    retried save callback for an older snapshot can never mark newer changes saved
	    or roll anything back.
	  - Only registered relics are saved. Unregistered relics are never written, so a
	    disconnect cannot bank fresh loot, and a relic another player recovered can never
	    be recreated from an old profile.
]]

local SpecimenCodec = require(script.Parent.SpecimenCodec)

local Sessions = {}
Sessions.__index = Sessions

-- The saved profile layout. ProfileStore fills missing fields from this (Reconcile).
function Sessions.template(schemaVersion: number)
	return {
		SchemaVersion = schemaVersion,
		Revision = 0,
		Relics = {},
		Loadout = {},
		Cooldowns = {},
	}
end

--[[
	options = {
		backend, store, schemaVersion, keyPrefix,
		now = () -> number,               -- unix seconds (DateTime-based in production)
		onStatus = (userId) -> (),        -- push new save status to the player
		onLost = (userId, reason) -> (),  -- session taken by another server or ended unexpectedly
		log = (message) -> (), warn = (message) -> (),
	}
]]
function Sessions.new(options)
	local self = setmetatable({
		backend = options.backend,
		store = options.store,
		schemaVersion = options.schemaVersion,
		keyPrefix = options.keyPrefix,
		now = options.now,
		onStatus = options.onStatus or function() end,
		onLost = options.onLost or function() end,
		log = options.log or print,
		warn = options.warn or warn,
		entries = {}, -- [userId] = entry
		keyToUser = {},
	}, Sessions)

	self.backend:onError(function(message, key)
		local userId = self.keyToUser[key]
		local entry = userId and self.entries[userId]
		if entry and entry.state == "Active" then
			entry.lastError = tostring(message)
			self.onStatus(userId)
		end
		self.warn(`[Hollowbound] Storage error for {key}: {message}`)
	end)
	return self
end

function Sessions:keyFor(userId: number): string
	return self.keyPrefix .. tostring(userId)
end

function Sessions:entry(userId: number)
	return self.entries[userId]
end

-- (true) or (false, playerFacingReason)
function Sessions:canMutate(userId: number): (boolean, string?)
	local entry = self.entries[userId]
	if not entry then
		return false, "Your saved data is not loaded."
	end
	if entry.state == "Loading" then
		return false, "Your saved relics are still loading."
	end
	if entry.state == "Lost" then
		return false, "Your session moved to another server. Rejoin to continue."
	end
	if entry.state ~= "Active" or entry.departed then
		return false, "Your saved data is not available."
	end
	if not entry.handle:isActive() then
		return false, "Your save session ended. Rejoin to continue."
	end
	return true
end

-- Status for the HUD: { mode, state, text }
--   mode  "Real" | "StudioMock" | "TestMock" | "Unavailable"
--   state "Loading" | "Saved" | "Saving" | "Pending" | "Retrying" | "Lost" | "Failed" | "None"
function Sessions:status(userId: number)
	local mode = self.backend.kind
	local entry = self.entries[userId]
	if not entry then
		return { mode = mode, state = "None", text = "Not loaded" }
	end
	local state, text
	if entry.state == "Loading" then
		state, text = "Loading", "Loading saved relics..."
	elseif entry.state == "Lost" then
		state, text = "Lost", "Session lost: rejoin"
	elseif entry.state == "Failed" then
		state, text = "Failed", "Load failed"
	elseif entry.lastError and entry.confirmedRevision < entry.revision then
		state, text = "Retrying", "Save failed, retrying"
	elseif entry.importantRevision > entry.confirmedRevision then
		state, text = "Saving", "Saving..."
	elseif entry.revision > entry.confirmedRevision then
		state, text = "Pending", "Saves on autosave or leave"
	else
		state, text = "Saved", "Saved"
	end
	if mode == "StudioMock" or mode == "TestMock" then
		text = "MOCK STORAGE (nothing persists): " .. text
	end
	return { mode = mode, state = state, text = text }
end

local function cooldownCopy(source, now: number)
	local copy = {}
	if typeof(source) == "table" then
		for abilityId, deadline in source do
			if typeof(abilityId) == "string" and typeof(deadline) == "number" and deadline > now then
				copy[abilityId] = deadline
			end
		end
	end
	return copy
end

-- Loads the player's profile. Yields. Returns (true) or (false, reason).
-- cancel() should return true once the player has left.
function Sessions:load(userId: number, cancel: () -> boolean, rules): (boolean, string?)
	if self.entries[userId] then
		return false, "A session for this player is already open"
	end
	local entry = {
		userId = userId,
		state = "Loading",
		departed = false,
		revision = 0,
		confirmedRevision = 0,
		importantRevision = 0,
		quarantine = {},
		cooldowns = {},
		handle = nil,
		lastError = nil,
	}
	self.entries[userId] = entry
	local key = self:keyFor(userId)
	self.keyToUser[key] = userId
	self.onStatus(userId)

	local handle, err = self.backend:startSession(key, function()
		return entry.departed or cancel()
	end, userId)

	if entry.departed or self.entries[userId] ~= entry then
		-- The player left while loading. Release the lock without changing the data.
		if handle then
			handle:endSession()
		end
		return false, "Player left before loading finished"
	end
	if not handle then
		entry.state = "Failed"
		self.onStatus(userId)
		return false, err or "Unknown load failure"
	end

	local data = handle.data
	if typeof(data.SchemaVersion) == "number" and data.SchemaVersion > self.schemaVersion then
		entry.state = "Failed"
		handle:endSession() -- data was not modified
		self.onStatus(userId)
		return false, "Saved data comes from a newer version of the game"
	end
	handle:reconcile() -- fills missing top-level fields only; never replaces existing data
	if typeof(data.Relics) ~= "table" then
		entry.state = "Failed"
		handle:endSession() -- nothing was modified beyond Reconcile
		self.onStatus(userId)
		return false, "Saved relic data is unreadable"
	end

	-- Restore registered relics exactly as saved.
	local restored = 0
	for recordKey, record in data.Relics do
		local specimen, reason = SpecimenCodec.decode(recordKey, record, userId)
		if specimen then
			local ok, restoreReason = self.store:restore(userId, specimen)
			if ok then
				restored += 1
			else
				entry.quarantine[recordKey] = record
				self.warn(`[Hollowbound] Kept saved relic {recordKey} for {userId} unloaded: {restoreReason}`)
			end
		else
			entry.quarantine[recordKey] = record
			self.warn(`[Hollowbound] Kept saved relic {recordKey} for {userId} unloaded: {reason}`)
		end
	end

	-- Loadout references must point at registered relics this player now carries.
	if typeof(data.Loadout) == "table" then
		for slotKey, specimenId in data.Loadout do
			local slot = tonumber(slotKey)
			local specimen = typeof(specimenId) == "string" and self.store:get(specimenId)
			if slot and specimen and specimen.registered and specimen.ownerUserId == userId then
				self.store:equip(userId, specimenId, slot, rules)
			end
		end
	end

	entry.cooldowns = cooldownCopy(data.Cooldowns, self.now())
	entry.handle = handle
	entry.revision = if typeof(data.Revision) == "number" then data.Revision else 0
	entry.confirmedRevision = entry.revision
	entry.importantRevision = entry.revision

	handle:onAfterSave(function(saved)
		if entry.handle ~= handle then
			return
		end
		local savedRevision = typeof(saved) == "table" and saved.Revision
		if typeof(savedRevision) == "number" and savedRevision > entry.confirmedRevision then
			entry.confirmedRevision = savedRevision
		end
		entry.lastError = nil
		if not entry.departed then
			self.onStatus(userId)
		end
	end)
	handle:onLastSave(function(reason)
		-- Shutdown, or another server asking for this profile: write the latest state
		-- right before ProfileStore's final save. Death penalties are never applied here.
		if (reason == "Shutdown" or reason == "External") and entry.state == "Active" then
			self:_commit(entry, false)
		end
	end)
	handle:onSessionEnd(function()
		if entry.departed or entry.state ~= "Active" then
			return -- our own endSession
		end
		if self.backend:isClosing() then
			entry.state = "Ended"
			return -- server shutdown; ProfileStore already saved
		end
		-- Another server took the session (or it ended unexpectedly). Stop all mutations
		-- here and drop this server's copy of the player's registered relics so they
		-- cannot exist in two places.
		entry.state = "Lost"
		for _, specimen in self.store:carried(userId) do
			if specimen.registered then
				self.store.specimens[specimen.id] = nil
			end
		end
		self.onStatus(userId)
		self.onLost(userId, "session ended on this server")
	end)

	entry.state = "Active"
	self.log(`[Hollowbound] Loaded {self.backend.kind} profile for {userId}: {restored} relic(s), revision {entry.revision}`)
	self.onStatus(userId)
	return true
end

function Sessions:_commit(entry, important: boolean): boolean
	local handle = entry.handle
	if entry.state ~= "Active" or not handle or not handle:isActive() then
		return false
	end
	local data = handle.data
	local userId = entry.userId

	local relics = {}
	for key, record in entry.quarantine do
		relics[key] = record
	end
	for _, specimen in self.store:carried(userId) do
		if specimen.registered then
			relics[specimen.id] = SpecimenCodec.encode(specimen)
		end
	end
	-- Anti-wipe guard: keep any previously saved relic missing from this snapshot.
	if typeof(data.Relics) == "table" then
		for key, record in data.Relics do
			if relics[key] == nil then
				relics[key] = record
				entry.quarantine[key] = record
				self.warn(`[Hollowbound] Refused to remove saved relic {key} from {userId}'s profile`)
			end
		end
	end

	local loadout = {}
	for slot, specimenId in self.store:loadout(userId) do
		local specimen = self.store:get(specimenId)
		if specimen and specimen.registered then
			loadout[tostring(slot)] = specimenId
		end
	end

	data.Relics = relics
	data.Loadout = loadout
	data.Cooldowns = cooldownCopy(entry.cooldowns, self.now())
	data.SchemaVersion = self.schemaVersion
	data.Revision = (if typeof(data.Revision) == "number" then data.Revision else 0) + 1
	entry.revision = data.Revision

	if important then
		entry.importantRevision = entry.revision
		handle:save()
	end
	self.onStatus(userId)
	return true
end

-- Writes the player's current state into their profile. Non-yielding.
-- important = request an immediate save (registration, service, appraisal, activation,
-- death); otherwise the change saves on the next autosave or when the player leaves.
function Sessions:commit(userId: number, important: boolean?): boolean
	local entry = self.entries[userId]
	if not entry then
		return false
	end
	return self:_commit(entry, important == true)
end

function Sessions:cooldownDeadline(userId: number, abilityId: string): number?
	local entry = self.entries[userId]
	return entry and entry.cooldowns[abilityId]
end

function Sessions:setCooldown(userId: number, abilityId: string, deadline: number)
	local entry = self.entries[userId]
	if entry then
		entry.cooldowns[abilityId] = deadline
	end
end

-- Remaining seconds per ability, for the HUD.
function Sessions:cooldownsRemaining(userId: number)
	local result = {}
	local entry = self.entries[userId]
	if not entry then
		return result
	end
	local now = self.now()
	for abilityId, deadline in entry.cooldowns do
		if deadline > now then
			result[abilityId] = deadline - now
		end
	end
	return result
end

-- Called once when the player leaves (after the departure rule has run).
-- Saves the final snapshot, ends the session, and removes the player's relics from
-- this server's memory. Safe to call repeatedly; only the first call does anything.
function Sessions:depart(userId: number)
	local entry = self.entries[userId]
	if not entry or entry.departed then
		return
	end
	if entry.state == "Active" then
		self:_commit(entry, false)
	end
	entry.departed = true
	self.entries[userId] = nil
	if entry.handle and entry.handle:isActive() then
		entry.handle:endSession()
	end
	if entry.state == "Active" then
		entry.state = "Ended"
	end
	self.store:forget(userId)
	self.keyToUser[self:keyFor(userId)] = nil
end

-- Users with an active session (for shutdown).
function Sessions:activeUsers()
	local list = {}
	for userId, entry in self.entries do
		if entry.state == "Active" then
			table.insert(list, userId)
		end
	end
	return list
end

return Sessions
