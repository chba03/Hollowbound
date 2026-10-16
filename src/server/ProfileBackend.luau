--[[
	Real storage backend: a thin server-only adapter over the vendored ProfileStore
	(MadStudioRoblox/ProfileStore, pinned in docs/DEPENDENCIES.md). Sessions talks to
	this interface, and the tests talk to MockBackend through the same interface:

	  backend.kind                 "Real" | "StudioMock" | "Unavailable"
	  backend:prepare()            yields until the kind is known
	  backend:startSession(key, cancel, userId?) -> handle?, errorMessage?   (yields)
	  backend:isClosing() -> boolean
	  backend:onError(fn(message, key))
	  handle.data                  the saved table; edit it only without yielding
	  handle:isActive() / :reconcile() / :save() / :endSession()
	  handle:onAfterSave(fn(savedData)) / :onLastSave(fn(reason)) / :onSessionEnd(fn())

	Upstream ProfileStore silently switches to an internal mock when DataStores are not
	accessible. This adapter checks ProfileStore.DataStoreState first and never lets that
	happen unnoticed: without access it either uses ProfileStore.Mock on purpose (Studio
	only, Config.Persistence.StudioMockWhenNoAccess, reported as "StudioMock") or refuses
	to start sessions ("Unavailable"), so a player is never given a blank profile.
]]

local RunService = game:GetService("RunService")

local ProfileStore = require(script.Parent.Vendor.ProfileStore)

local ProfileBackend = {}
ProfileBackend.__index = ProfileBackend

local Handle = {}
Handle.__index = Handle

function Handle:isActive(): boolean
	return self.profile:IsActive()
end

function Handle:reconcile()
	self.profile:Reconcile()
end

function Handle:save()
	if self.profile:IsActive() then
		self.profile:Save()
	end
end

function Handle:endSession()
	self.profile:EndSession()
end

function Handle:onAfterSave(fn)
	return self.profile.OnAfterSave:Connect(fn)
end

function Handle:onLastSave(fn)
	return self.profile.OnLastSave:Connect(fn)
end

function Handle:onSessionEnd(fn)
	return self.profile.OnSessionEnd:Connect(fn)
end

local function wrap(profile)
	local handle = setmetatable({ profile = profile }, Handle)
	-- Data is read through the profile so a ProfileStore-side table swap is never missed.
	return setmetatable(handle, {
		__index = function(_, key)
			if key == "data" then
				return profile.Data
			end
			return Handle[key]
		end,
	})
end

-- options = { storeName, template, studioMockWhenNoAccess, accessWaitTimeout, sameServerReloadAttempts }
function ProfileBackend.new(options)
	local self = setmetatable({
		kind = "Pending",
		accessState = "NotReady",
		options = options,
		store = ProfileStore.New(options.storeName, options.template),
	}, ProfileBackend)
	return self
end

function ProfileBackend:prepare()
	if self.kind ~= "Pending" then
		return
	end
	local started = os.clock()
	while ProfileStore.DataStoreState == "NotReady" and os.clock() - started < self.options.accessWaitTimeout do
		task.wait(0.1)
	end
	self.accessState = ProfileStore.DataStoreState
	if self.accessState == "Access" then
		self.kind = "Real"
	elseif RunService:IsStudio() and self.options.studioMockWhenNoAccess then
		self.kind = "StudioMock"
	else
		self.kind = "Unavailable"
	end
end

function ProfileBackend:isClosing(): boolean
	return ProfileStore.IsClosing == true
end

function ProfileBackend:onError(fn)
	return ProfileStore.OnError:Connect(function(message, _storeName, key)
		fn(message, key)
	end)
end

function ProfileBackend:onOverwrite(fn)
	return ProfileStore.OnOverwrite:Connect(function(_storeName, key)
		fn(key)
	end)
end

function ProfileBackend:startSession(key: string, cancel: () -> boolean, userId: number?)
	self:prepare()
	if self.kind == "Unavailable" then
		return nil, `DataStores are not available (state: {self.accessState})`
	end
	local source = if self.kind == "StudioMock" then self.store.Mock else self.store

	for _ = 1, self.options.sameServerReloadAttempts do
		local ok, result = pcall(source.StartSessionAsync, source, key, { Cancel = cancel })
		if ok then
			if result == nil then
				return nil, "Loading was cancelled or timed out"
			end
			if userId and result:IsActive() then
				result:AddUserId(userId) -- GDPR association, as recommended upstream
			end
			return wrap(result), nil
		end
		-- A quick rejoin can race this server's own session end for the same key.
		if string.find(tostring(result), "already loaded in this session", 1, true) and not cancel() then
			task.wait(1)
		else
			return nil, tostring(result)
		end
	end
	return nil, "This server is still closing your previous session"
end

return ProfileBackend
