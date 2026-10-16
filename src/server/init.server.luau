--[[
	Hollowbound server entry point (milestone 5).
	Milestone 5: WorldInfo picks the active world first (the installed vertical world, or
	the legacy runtime dev map); every service then binds only to that world's markers.
	The vertical world is installed in edit mode (World/Installer) and never built here.
	The server owns specimen generation, inventories, ownership, registration, final
	death, service, appraisal, activation, loadouts, abilities, and saved profiles, plus
	(milestone 4) expeditions, health and the downed stage, melee combat, creatures,
	guardian encounters, ordinary supplies, and revives.
	Registered relics persist through ProfileStore (Sessions + ProfileBackend);
	unregistered relics and ordinary items live only in server memory.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local LoadoutRules = require(Shared:WaitForChild("LoadoutRules"))
local Abilities = require(script.Abilities)
local Falls = require(script.Falls)
local Outfitter = require(script.Outfitter)
local Poses = require(script.Poses)
local Spawning = require(script.Spawning)
local WorldInfo = require(script.WorldInfo)
local Busy = require(script.Busy)
local Combat = require(script.Combat)
local Creatures = require(script.Creatures)
local Defeat = require(script.Defeat)
local DevMap = require(script.DevMap)
local Encounters = require(script.Encounters)
local Expedition = require(script.Expedition)
local FieldActions = require(script.FieldActions)
local Gear = require(script.Gear)
local Guard = require(script.Guard)
local ProfileBackend = require(script.ProfileBackend)
local Registration = require(script.Registration)
local RelicActions = require(script.RelicActions)
local RelicStore = require(script.RelicStore)
local RelicView = require(script.RelicView)
local Rescue = require(script.Rescue)
local SelfTest = require(script.SelfTest)
local ServerNet = require(script.ServerNet)
local ServiceStation = require(script.ServiceStation)
local Sessions = require(script.Sessions)
local Vitals = require(script.Vitals)
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
-- Pick the active world before anything binds to markers.
local worldMode = WorldInfo.resolve()
local legacy = worldMode == "Legacy"

-- Legacy dev map and fixtures: only when the legacy world is active (Studio only).
if inStudio and legacy and Config.Dev.BuildPlaceholderMap then
	DevMap.ensure()
end
if inStudio and legacy and Config.Dev.BuildServiceStation then
	DevMap.ensureServiceStation()
end
if inStudio and legacy and Config.Dev.BuildRelicFixtures then
	DevMap.ensureRelicFixtures()
end
if inStudio and legacy and Config.Dev.BuildSupplyStation then
	DevMap.ensureSupplyStation()
end
if inStudio and legacy and Config.Dev.BuildEncounterFixtures then
	DevMap.ensureEncounterFixtures()
end
Spawning.start(worldMode)

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
	local state = RelicView.state(store, sessions, player, Zones.playerAtDesk(player))
	-- Milestone 4: ordinary items (session-only) for the HUD.
	local weaponId = Gear.weapon(player)
	state.gear = {
		items = Gear.contents(player),
		weapon = if weaponId then Config.Items[weaponId].displayName else "",
		selfRescuesLeft = Expedition.selfRescuesLeft(player),
	}
	return state
end)
WorldRelics.start(store)
Registration.start(store, sessions)
Zones.start(store)
ServiceStation.start(store, sessions)
Abilities.start(store, sessions, unixNow)
RelicActions.start(store, sessions)
Defeat.start(store)

-- Milestone 4 systems.
Busy.start()
Vitals.start()
Expedition.start()
Gear.start()
Rescue.start()
Creatures.start()
Combat.start()
Encounters.start(store)
FieldActions.start()

-- Milestone 5.
Falls.start()
Poses.start()
Outfitter.start()

-- Going down ends relic effects that need a standing user.
Vitals.onDowned(function(player)
	Abilities.endAll(player.UserId)
	ServerNet.pushState(player)
end)
Vitals.onRevived(function(player)
	ServerNet.pushState(player)
end)
-- Final death (bleedout, reset, void, field departure): supplies drop next to the
-- relic drops, and the expedition run ends. Both run once, inside Defeat's guard.
Defeat.onFinalDeath(function(player, point)
	Gear.dropAll(player, point + Vector3.new(2.5, 0, 0))
	Expedition.finishRun(player, "final death")
end)

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
	-- A downed player leaving outside town gets the same single final death.
	Defeat.handleDeparture(player, mode)
	-- Ordinary items are session-only: whatever was not dropped by a final death above
	-- (town departure, shutdown, lost session) is discarded.
	Gear.discard(player)
	Expedition.finishRun(player, "left the game")
	sessions:depart(player.UserId)
end)

print(`[Hollowbound] Milestone 5 server ready (world: {worldMode}, storage: {backend.kind}, resolving in background).`)
