--[[
	Saved player data through ProfileStore (loleris' maintained successor to
	ProfileService, vendored in Vendor/). One session-locked profile per player.

	What is saved, and why:
	  - Cash and the three upgrade levels. Stat values (rope length in studs, etc.) are
	    derived from levels through Progression, so rebalancing Config never needs a
	    data migration.
	  - Registered relics only. Decided: a new relic stays unsecured until registered in
	    town, so an unregistered relic never reaches the DataStore. If the player leaves
	    mid-expedition, RelicStore forfeits it (Open: leaving rules are undecided).
	  - Display slot assignments.

	In Studio without API access, ProfileStore uses an in-memory mock automatically, so
	playtests work but nothing persists between sessions. To test real saving, publish
	the place and turn on Game Settings > Security > Enable Studio Access to API Services.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Perks = require(Shared:WaitForChild("Perks"))
local Progression = require(Shared:WaitForChild("Progression"))
local ProfileStore = require(script.Parent.Vendor.ProfileStore)
local SpecimenFactory = require(script.Parent.SpecimenFactory)

local PlayerData = {}

-- Data schema. ProfileStore copies this for new players and Reconcile() fills any
-- field missing from older saves. Rules from ProfileStore: no Instances or userdata,
-- no mixed or gapped arrays, string or number keys only.
PlayerData.Template = {
	SchemaVersion = 1,

	Cash = 0,
	RopeLengthLevel = 1, -- index into Config.Rope.LengthLevels
	RopeSpeedLevel = 1, -- index into Config.Rope.SpeedLevels (Speed gained per pull)
	Speed = 0, -- trained on the Hauling Rig; sets climb speed (Progression.climbSpeed)
	BaseSlotsLevel = 1, -- index into Config.Base.SlotLevels

	-- Owned relics: [specimenId] = {
	--   typeId, quality, rarity, traits = { [traitId] = number }, layer,
	--   appraised, activated, registered, condition, charge, foundAt, registeredAt }
	-- Registered relics only. Traits are copied once and never edited.
	Relics = {},

	-- Placed relics: [tostring(slot)] = specimenId. String keys, because slots can
	-- have gaps and ProfileStore cannot save gapped arrays.
	Placed = {},

	Stats = {
		DeepestDepth = 0,
		RelicsRegistered = 0,
		CashEarned = 0,
	},

	-- Pickaxes (server Arsenal): owned ids and the equipped one. The first is free.
	Pickaxes = {
		Owned = { Gardener = true },
		Equipped = "Gardener",
	},
	-- Other gear bought at the Forge (server Arsenal, Grapple).
	Gear = {
		Grapple = false,
	},

	-- Store (server Store). Timed boosts: [boostId] = server time the boost ends.
	Boosts = {},
	-- Recent purchase receipt ids, so a retried receipt never grants twice.
	Receipts = {},
	-- Weekly limited offers: the week number and purchases per offer that week.
	Shop = {
		Week = 0,
		Bought = {},
	},
}

local MAX_STAT = 2 ^ 62 -- leaderboard values are 64-bit integers

local profileStore = ProfileStore.New(Config.Data.StoreName, PlayerData.Template)
local profiles: { [Player]: any } = {}
local loadedHandlers: { (Player) -> () } = {}
local store

-- Leaderboard and attributes the client reads. Attributes replicate to every client;
-- nothing here is secret.
function PlayerData.publish(player: Player)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	player:SetAttribute("HB_Cash", math.floor(data.Cash))
	player:SetAttribute("HB_Deepest", data.Stats.DeepestDepth)
	player:SetAttribute("HB_RopeLengthLevel", data.RopeLengthLevel)
	player:SetAttribute("HB_RopeSpeedLevel", data.RopeSpeedLevel)
	player:SetAttribute("HB_BaseSlotsLevel", data.BaseSlotsLevel)
	player:SetAttribute("HB_RopeLength", Progression.value("RopeLength", data.RopeLengthLevel))
	PlayerData.publishSpeed(player)
	player:SetAttribute("HB_Slots", Progression.value("BaseSlots", data.BaseSlotsLevel))

	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash")
	if cash and cash:IsA("StringValue") then
		cash.Value = Progression.formatCash(data.Cash) -- past 64-bit range late game, so shown as text
	end
end

-- Speed, climb speed, and the Speed leaderboard column. Cheap enough to run on every
-- pull at the Hauling Rig.
function PlayerData.publishSpeed(player: Player)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	player:SetAttribute("HB_Speed", data.Speed)
	-- Climb speed comes from Speed, times the Swift Climber pass and climb boost (Perks).
	player:SetAttribute("HB_RopeSpeed", math.min(Progression.climbSpeed(data.Speed) * Perks.climb(player), Config.Speed.MaxWithPerks))
	local leaderstats = player:FindFirstChild("leaderstats")
	local speed = leaderstats and leaderstats:FindFirstChild("Speed")
	if speed then
		speed.Value = math.min(math.floor(data.Speed), MAX_STAT)
	end
end

local function restoreRelics(player: Player, data)
	local userId = player.UserId
	for specimenId, saved in data.Relics do
		local specimen = SpecimenFactory.deserialize(specimenId, saved)
		if specimen and specimen.registered and not store:get(specimenId) then
			store:restore(specimen, userId)
		else
			warn(`[Hollowbound] Skipped saved relic {specimenId} for {player.Name}: unknown type, unregistered, or duplicate`)
		end
	end

	local capacity = Progression.value("BaseSlots", data.BaseSlotsLevel)
	for slotKey, specimenId in table.clone(data.Placed) do
		local slot = tonumber(slotKey)
		local ok = slot ~= nil and store:place(userId, specimenId, slot, capacity)
		if not ok then
			data.Placed[slotKey] = nil
		end
	end
end

local function onPlayerAdded(player: Player)
	local profile = profileStore:StartSessionAsync(Config.Data.KeyPrefix .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		-- Another server holds the session, or the player left while loading.
		if player.Parent == Players then
			player:Kick("Your Hollowbound data could not be loaded. Please rejoin.")
		end
		return
	end

	profile:AddUserId(player.UserId) -- GDPR
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Your Hollowbound session ended (opened in another server?). Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profiles[player] = profile

	-- The server leaderboard (Roblox's player list): Speed first, so it sorts by Speed.
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local speed = Instance.new("IntValue")
	speed.Name = "Speed"
	speed.Parent = leaderstats
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Parent = leaderstats
	leaderstats.Parent = player

	restoreRelics(player, profile.Data)
	PlayerData.publish(player)
	print(`[Hollowbound] Loaded data for {player.Name} (store: {ProfileStore.DataStoreState})`)

	for _, handler in loadedHandlers do
		task.spawn(handler, player)
	end
end

local function onPlayerRemoving(player: Player)
	local forfeited = store:releasePlayer(player.UserId)
	if forfeited > 0 then
		print(`[Hollowbound] {player.Name} left carrying {forfeited} unsecured relic(s); forfeited`)
	end
	local profile = profiles[player]
	if profile then
		profile:EndSession()
	end
end

function PlayerData.start(theStore)
	store = theStore
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- Runs handler(player) once each player's data is loaded and their relics restored.
function PlayerData.onLoaded(handler: (Player) -> ())
	table.insert(loadedHandlers, handler)
	for player in profiles do
		task.spawn(handler, player)
	end
end

-- The live Profile.Data table, or nil while loading. Changes are saved automatically.
function PlayerData.get(player: Player)
	local profile = profiles[player]
	return if profile and profile:IsActive() then profile.Data else nil
end

function PlayerData.addCash(player: Player, amount: number)
	local data = PlayerData.get(player)
	if not data or amount <= 0 then
		return
	end
	data.Cash += amount
	data.Stats.CashEarned += amount
end

-- Deducts cash if the player can afford it. Does not yield.
function PlayerData.trySpend(player: Player, amount: number): boolean
	local data = PlayerData.get(player)
	if not data or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	return true
end

-- Called after registration: registered relics are the only relics that are saved.
function PlayerData.saveSpecimen(player: Player, specimen)
	local data = PlayerData.get(player)
	if not data or not specimen.registered then
		return
	end
	if data.Relics[specimen.id] == nil then
		data.Stats.RelicsRegistered += 1
	end
	data.Relics[specimen.id] = SpecimenFactory.serialize(specimen)
end

function PlayerData.setPlaced(player: Player, slot: number, specimenId: string?)
	local data = PlayerData.get(player)
	if data then
		data.Placed[tostring(slot)] = specimenId
	end
end

function PlayerData.recordDepth(player: Player, depth: number)
	local data = PlayerData.get(player)
	if data and depth > data.Stats.DeepestDepth then
		data.Stats.DeepestDepth = math.floor(depth)
		player:SetAttribute("HB_Deepest", data.Stats.DeepestDepth)
	end
end

return PlayerData
