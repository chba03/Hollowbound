--[[
	TEST-ONLY storage backend. Never used by gameplay code: init.server.luau always uses
	ProfileBackend. This mock lives entirely in Luau memory, touches no DataStore, and
	exists so the tests can inject failures that real storage cannot produce on demand.

	It imitates the ProfileStore behaviours Sessions relies on:
	  - one active session per key; a new session steals the lock and ends the old one
	    (the old handle fires onSessionEnd and its later saves are rejected as stale)
	  - saves copy the data; onAfterSave receives that copy
	  - endSession fires onLastSave("Manual"), saves, then onSessionEnd
	Failure injection:
	  backend.failLoads = n       -> the next n startSession calls fail
	  backend.failSaves = true    -> saves fail (onError fires; nothing is written)
	  backend.deferCallbacks = true -> onAfterSave callbacks queue until flushCallbacks(order)
	  backend.closing = true      -> isClosing() reports shutdown
]]

local MockBackend = {}
MockBackend.__index = MockBackend

local function deepCopy(value)
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function reconcile(target, template)
	for k, v in template do
		if target[k] == nil then
			target[k] = deepCopy(v)
		elseif typeof(v) == "table" and typeof(target[k]) == "table" then
			reconcile(target[k], v)
		end
	end
end

function MockBackend.new(template)
	return setmetatable({
		kind = "TestMock",
		template = template,
		saved = {}, -- [key] = deep copy of the last successful save
		active = {}, -- [key] = handle
		failLoads = 0,
		failSaves = false,
		deferCallbacks = false,
		pending = {}, -- queued { fn, data }
		closing = false,
		errorListeners = {},
		saveCount = 0,
	}, MockBackend)
end

function MockBackend:prepare() end

function MockBackend:isClosing(): boolean
	return self.closing
end

function MockBackend:onError(fn)
	table.insert(self.errorListeners, fn)
end

local Handle = {}
Handle.__index = Handle

local function fire(list, ...)
	for _, fn in list do
		fn(...)
	end
end

function Handle:isActive(): boolean
	return self.backend.active[self.key] == self
end

function Handle:reconcile()
	reconcile(self.data, self.backend.template)
end

function Handle:save()
	local backend = self.backend
	if not self:isActive() then
		return false -- stale: another session owns this key now
	end
	if backend.failSaves then
		fire(backend.errorListeners, "mock save failure", self.key)
		return false
	end
	local copy = deepCopy(self.data)
	backend.saved[self.key] = copy
	backend.saveCount += 1
	for _, fn in self.afterSave do
		if backend.deferCallbacks then
			table.insert(backend.pending, { fn = fn, data = deepCopy(copy) })
		else
			fn(deepCopy(copy))
		end
	end
	return true
end

function Handle:endSession()
	if not self:isActive() then
		return
	end
	fire(self.lastSave, "Manual")
	self:save()
	self.backend.active[self.key] = nil
	fire(self.sessionEnd)
end

function Handle:onAfterSave(fn)
	table.insert(self.afterSave, fn)
end

function Handle:onLastSave(fn)
	table.insert(self.lastSave, fn)
end

function Handle:onSessionEnd(fn)
	table.insert(self.sessionEnd, fn)
end

function MockBackend:startSession(key: string, cancel: () -> boolean)
	if cancel() then
		return nil, "cancelled"
	end
	if self.failLoads > 0 then
		self.failLoads -= 1
		return nil, "mock load failure"
	end
	local previous = self.active[key]
	if previous then
		-- Session steal: the old holder loses its lock without a final save.
		self.active[key] = nil
		fire(previous.sessionEnd)
	end
	local stored = self.saved[key]
	local handle = setmetatable({
		backend = self,
		key = key,
		data = if stored then deepCopy(stored) else deepCopy(self.template),
		afterSave = {},
		lastSave = {},
		sessionEnd = {},
	}, Handle)
	self.active[key] = handle
	return handle, nil
end

-- Delivers queued onAfterSave callbacks. order "reverse" delivers newest first, which
-- simulates late callbacks arriving after newer ones.
function MockBackend:flushCallbacks(order: string?)
	local queue = self.pending
	self.pending = {}
	if order == "reverse" then
		for i = #queue, 1, -1 do
			queue[i].fn(queue[i].data)
		end
	else
		for _, item in queue do
			item.fn(item.data)
		end
	end
end

return MockBackend
