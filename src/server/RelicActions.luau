--[[
	Handles RelicAction requests from clients: Equip, Unequip, Use, Appraise, Activate.
	Every argument is checked for type here and again by the store, so forged requests
	(wrong types, other players' relics, duplicate slots, made-up IDs) fail with a reason.
	Requests are rate limited per player.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local LoadoutRules = require(Shared:WaitForChild("LoadoutRules"))
local Abilities = require(script.Parent.Abilities)
local Guard = require(script.Parent.Guard)
local RelicDefs = require(script.Parent.RelicDefs)
local RelicStore = require(script.Parent.RelicStore)
local ServerNet = require(script.Parent.ServerNet)
local Zones = require(script.Parent.Zones)

local RelicActions = {}

local store
local sessions
local rules = LoadoutRules.forStore()
local buckets: { [Player]: { tokens: number, at: number } } = {}

local REASONS = {
	NotFound = "That relic is not available.",
	NotOwner = "That relic is not yours.",
	NotCarried = "You are not carrying that relic.",
	BadSlot = "That slot does not exist.",
	SlotEmpty = "That slot is already empty.",
	AlreadyEquipped = "That relic is already equipped. Unequip it first.",
	NotEquippable = "That relic cannot be equipped.",
	AlreadyAppraised = "That relic is already appraised.",
	ActivationNotRequired = "This relic works without activation.",
	AlreadyActivated = "That relic is already activated.",
}

local function classLimitMessage(): string
	local limit = Config.Loadout.MaxPerClass.Exceptional or 0
	return `Only {limit} exceptional relic(s) can be equipped at a time.`
end

local function allowRequest(player: Player): boolean
	local now = os.clock()
	local bucket = buckets[player]
	if not bucket then
		bucket = { tokens = Config.Requests.MaxPerSecond, at = now }
		buckets[player] = bucket
	end
	bucket.tokens = math.min(Config.Requests.MaxPerSecond, bucket.tokens + (now - bucket.at) * Config.Requests.MaxPerSecond)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function name(specimen): string
	return `{RelicDefs.displayName(specimen.typeId)} ({specimen.rarity})`
end

local function equip(player: Player, specimenId: any, slot: any)
	local userId = player.UserId
	local ok, reason, replaced = store:equip(userId, specimenId, slot, rules)
	if not ok then
		if reason == "ClassLimit" then
			return false, classLimitMessage()
		end
		return false, REASONS[reason :: string] or "Could not equip that relic."
	end
	if replaced then
		Abilities.endEffectsFor(userId, { replaced })
	end
	sessions:commit(userId, false)
	local specimen = store:get(specimenId)
	return true, `Equipped {name(specimen)} in slot {slot}.`
end

local function unequip(player: Player, slot: any)
	local userId = player.UserId
	local ok, reason, removed = store:unequip(userId, slot, rules)
	if not ok then
		return false, REASONS[reason :: string] or "Could not unequip."
	end
	Abilities.endEffectsFor(userId, { removed :: string })
	sessions:commit(userId, false)
	return true, `Slot {slot} is now empty.`
end

-- Appraisal and activation happen at a town terminal or service station.
local function requireDesk(player: Player): (boolean, string?)
	if not Zones.playerAtDesk(player) then
		return false, "Go to a registry terminal or service station in town."
	end
	return true
end

local function appraise(player: Player, specimenId: any)
	local atDesk, why = requireDesk(player)
	if not atDesk then
		return false, why
	end
	local userId = player.UserId
	local specimen = typeof(specimenId) == "string" and store:get(specimenId)
	local before = specimen and RelicStore.fingerprint(specimen)
	local ok, reason = store:appraise(userId, specimenId)
	if not ok then
		return false, REASONS[reason :: string] or "Could not appraise that relic."
	end
	assert(RelicStore.fingerprint(specimen) == before, "Appraisal changed a specimen")
	sessions:commit(userId, specimen.registered)
	print(`[Hollowbound] {player.Name} appraised {RelicStore.fingerprint(specimen)}`)
	return true, `Appraised {name(specimen)}: its traits are now visible to you.`
end

local function activate(player: Player, specimenId: any)
	local atDesk, why = requireDesk(player)
	if not atDesk then
		return false, why
	end
	local userId = player.UserId
	local specimen = typeof(specimenId) == "string" and store:get(specimenId)
	local requires = specimen and RelicDefs.requiresActivation(specimen.typeId) or false
	local ok, reason = store:activate(userId, specimenId, requires)
	if not ok then
		return false, REASONS[reason :: string] or "Could not activate that relic."
	end
	sessions:commit(userId, specimen.registered)
	print(`[Hollowbound] {player.Name} activated {specimen.id}`)
	return true, `Activated {name(specimen)}. It can now be used when equipped.`
end

local HANDLERS = {
	Equip = function(player, specimenId, slot)
		return equip(player, specimenId, slot)
	end,
	Unequip = function(player, slot)
		return unequip(player, slot)
	end,
	Use = function(player, slot)
		return Abilities.use(player, slot)
	end,
	Appraise = function(player, specimenId)
		return appraise(player, specimenId)
	end,
	Activate = function(player, specimenId)
		return activate(player, specimenId)
	end,
}

function RelicActions.handle(player: Player, action: any, a: any, b: any): (boolean, string)
	if not allowRequest(player) then
		return false, "Too many requests. Slow down."
	end
	if typeof(action) ~= "string" or HANDLERS[action] == nil then
		return false, "Unknown action."
	end
	if action ~= "Use" then
		local allowed, blocked = Guard.check(player)
		if not allowed then
			return false, blocked :: string
		end
	end
	local ok, message = HANDLERS[action](player, a, b)
	ServerNet.pushState(player)
	return ok, message
end

function RelicActions.start(theStore, theSessions)
	store = theStore
	sessions = theSessions
	ServerNet.onRelicAction(RelicActions.handle)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return RelicActions
