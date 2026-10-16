--[[
	Hollowbound server entry point (milestone 3).
	The server owns specimen generation, inventories, ownership, registration, final
	death, service, appraisal, activation, loadouts, abilities, and saved profiles.
	Registered relics persist through ProfileStore (Sessions + ProfileBackend);
	unregistered relics live only in server memory.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local LoadoutRules = require(Shared:WaitForChild("LoadoutRules"))
local Abilities = require(script.Abilities)
local Defeat = require(script.Defeat)
local DevMap = require(script.DevMap)
local Guard = require(script.Guard)
local ProfileBackend = require(script.ProfileBackend)
local Registration = require(script.Registration)
local RelicActions = require(script.RelicActions)
local RelicStore = require(script.RelicStore)
local RelicView = require(script.RelicView)
local SelfTest = require(script.SelfTest)
local ServerNet = require(script.ServerNet)
local ServiceStation = require(script.ServiceStation)
local Sessions = require(script.Sessions)
local WorldRelics = require(script.WorldRelics)
local Zones = require(script.Zones)

local inStudio = RunService:IsStudio()

-- Wall-clock seconds, shared across servers, for saved cooldown deadlines.
local function unixNow(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

if inStudio and Config.Dev.RunSelfTest then
	SelfTest.run() -- isolated mock storage only; never touches DataStores
end

-- Build the dev map before WorldRelics so the relic spawn parts exist.
if inStudio and Config.Dev.BuildPlaceholderMap then
	DevMap.ensure()
end
if inStudio and Config.Dev.BuildServiceStation then
	DevMap.ensureServiceStation()
end
if inStudio and Config.Dev.BuildRelicFixtures then
	DevMap.ensureRelicFixtures()
end

local store = RelicStore.new()
local backend = ProfileBackend.new({
	storeName = Config.Persistence.StoreName,
	template = Sessions.template(Config.Persistence.SchemaVersion),
	studioMockWhenNoAccess = Config.Persistence.StudioMockWhenNoAccess,
	accessWaitTimeout = Config.Persistence.AccessWaitTimeout,
	sameServerReloadAttempts = Config.Persistence.SameServerReloadAttempts,
})
backend:onOverwrite(function(key)
	warn(`[Hollowbound] ProfileStore replaced unreadable data at key {key}`)
end)

local sessions = Sessions.new({
	backend = backend,
	store = store,
	schemaVersion = Config.Persistence.SchemaVersion,
	keyPrefix = Config.Persistence.KeyPrefix,
	now = unixNow,
	onStatus = function(userId)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			ServerNet.pushState(player)
		end
	end,
	onLost = function(userId)
		Abilities.endAll(userId)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			player:Kick("Your Hollowbound profile was opened on another server. Your registered relics are safe; please rejoin.")
		end
	end,
})
Guard.setSessions(sessions)

ServerNet.start(function(player)
	return RelicView.state(store, sessions, player, Zones.playerAtDesk(player))
end)
WorldRelics.start(store)
Registration.start(store, sessions)
Zones.start(store)
ServiceStation.start(store, sessions)
Abilities.start(store, sessions, unixNow)
RelicActions.start(store, sessions)
Defeat.start(store)

local function onPlayerAdded(player: Player)
	local ok, err = sessions:load(player.UserId, function()
		return player.Parent ~= Players
	end, LoadoutRules.forStore())
	if ok then
		if backend.kind == "StudioMock" then
			ServerNet.notify(player, "MOCK STORAGE: Studio has no DataStore access, so nothing will be saved.", "error")
			warn("[Hollowbound] Using ProfileStore.Mock on purpose (Studio without API access). Nothing persists.")
		end
		local waiting = 0
		for _, specimen in store:carried(player.UserId) do
			if specimen.needsService then
				waiting += 1
			end
		end
		if waiting > 0 then
			ServerNet.notify(player, `{waiting} registered relic(s) need service in town before use.`, "info")
		end
		ServerNet.pushState(player)
	elseif player.Parent == Players then
		warn(`[Hollowbound] Could not load {player.Name}: {err}`)
		-- No blank profile is ever used in place of saved data.
		player:Kick(`Hollowbound could not load your saved relics, so nothing was changed. Please rejoin. ({err})`)
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(onPlayerAdded, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Known whole-server shutdown: save everyone as is. No death penalties.
local shuttingDown = false
game:BindToClose(function()
	shuttingDown = true
	for _, userId in sessions:activeUsers() do
		sessions:commit(userId, false)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local entry = sessions:entry(player.UserId)
	local mode
	if shuttingDown or backend:isClosing() then
		mode = "Shutdown"
	elseif entry and entry.state == "Lost" then
		mode = "Lost"
	elseif not entry or entry.state ~= "Active" then
		mode = "NotLoaded"
	else
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local zone = if root and root:IsA("BasePart") then Zones.zoneAt(root.Position) else player:GetAttribute("HB_Zone")
		mode = if zone == "Town" then "Town" else "Field"
	end
	-- Temporary departure rule first (it may change relics), then save and clean up.
	Defeat.handleDeparture(player, mode)
	sessions:depart(player.UserId)
end)

print(`[Hollowbound] Milestone 3 server ready (storage: {backend.kind}, resolving in background).`)
