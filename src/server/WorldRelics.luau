--[[
	Spawns the test specimens in the expedition area, places relics dropped on final
	death, and handles pickup. A dropped relic is the same specimen record with its
	owner cleared, so recovery uses the same validation and claim as a first pickup.

	Pickup requests come from the server-side ProximityPrompt.Triggered event, or, in
	Studio, from the dev remote. Both use tryPickup, which checks the character,
	distance, availability, and ownership before claiming.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Characters = require(script.Parent.Characters)
local Guard = require(script.Parent.Guard)
local RelicStore = require(script.Parent.RelicStore)
local ServerNet = require(script.Parent.ServerNet)
local SpecimenFactory = require(script.Parent.SpecimenFactory)

local WorldRelics = {}

local store
local folder: Folder
local partsById: { [string]: BasePart } = {}
local claimedListeners: { (Player, string) -> () } = {}

-- fn(player, specimenId) after a successful pickup (Encounters watches for its rewards).
function WorldRelics.onClaimed(fn: (Player, string) -> ())
	table.insert(claimedListeners, fn)
end

local REJECTIONS = {
	NotFound = "That relic does not exist.",
	AlreadyOwned = "Someone else picked that relic up first.",
	Unavailable = "That relic is no longer there.",
}

local function rarityColor(rarityId: string): Color3
	for _, tier in Config.Rarities do
		if tier.id == rarityId then
			return tier.color
		end
	end
	return Color3.new(1, 1, 1)
end

local function spawnWorldPart(specimen, position: Vector3, dropped: boolean)
	local relicType = Config.RelicTypes[specimen.typeId]

	local part = Instance.new("Part")
	part.Name = "Relic_" .. specimen.id
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.6, 1.6, 1.6)
	part.Material = Enum.Material.Neon
	part.Color = rarityColor(specimen.rarity)
	part.Anchored = true
	part.CanCollide = false
	part.Position = position
	part:SetAttribute("SpecimenId", specimen.id)

	-- The prompt only shows type and rarity, which are visible before appraisal.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = `{relicType.displayName} ({specimen.rarity})` .. (if dropped then ", dropped" else "")
	prompt.MaxActivationDistance = Config.Pickup.PromptMaxDistance
	prompt.HoldDuration = Config.Pickup.HoldDuration
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		WorldRelics.tryPickup(player, specimen.id, "prompt")
	end)

	CollectionService:AddTag(part, Config.Tags.WorldRelic)
	part.Parent = folder
	partsById[specimen.id] = part
end

-- Returns true if this player now owns the specimen.
-- Nothing in this function yields before store:claim, so competing requests run in
-- order and only one can succeed.
function WorldRelics.tryPickup(player: Player, specimenId: any, source: string): boolean
	if typeof(specimenId) ~= "string" then
		return false
	end

	local allowed, blocked = Guard.checkActive(player)
	if not allowed then
		ServerNet.notify(player, blocked :: string, "error")
		return false
	end

	local root = Characters.liveRoot(player)
	if not root then
		ServerNet.notify(player, "You need a living character to pick that up.", "error")
		return false
	end

	local part = partsById[specimenId]
	if not part then
		ServerNet.notify(player, REJECTIONS.Unavailable, "error")
		print(`[Hollowbound] Rejected pickup by {player.Name} ({source}): {specimenId} not in world`)
		return false
	end

	local distance = (root.Position - part.Position).Magnitude
	if distance > Config.Pickup.ServerMaxDistance then
		ServerNet.notify(
			player,
			string.format("Too far away to pick that up (%.0f studs, limit %d).", distance, Config.Pickup.ServerMaxDistance),
			"error"
		)
		print(string.format("[Hollowbound] Rejected pickup by %s (%s): distance %.1f", player.Name, source, distance))
		return false
	end

	local ok, reason = store:claim(specimenId, player.UserId)
	if not ok then
		ServerNet.notify(player, REJECTIONS[reason :: string] or "You cannot pick that up.", "error")
		print(`[Hollowbound] Rejected pickup by {player.Name} ({source}): {reason}`)
		return false
	end

	partsById[specimenId] = nil
	part:Destroy()

	local specimen = store:get(specimenId)
	local name = Config.RelicTypes[specimen.typeId].displayName
	ServerNet.notify(player, `Picked up {name} ({specimen.rarity}). Unsecured until registered in town.`, "success")
	ServerNet.pushState(player)
	for _, listener in claimedListeners do
		task.spawn(listener, player, specimenId)
	end
	if Config.Dev.LogTraitsToServerOutput then
		print(`[Hollowbound] {player.Name} picked up {RelicStore.identityAndStates(specimen)} via {source}`)
	else
		print(`[Hollowbound] {player.Name} picked up {specimenId} via {source}`)
	end
	return true
end

-- Places a specimen that final death returned to the world. The record must already
-- be ownerless and in the world. Refuses to create a second world part for it.
-- Places a newly generated encounter reward (ownerless, in the world) for normal pickup.
function WorldRelics.spawnReward(specimen, position: Vector3): boolean
	if specimen.ownerUserId ~= nil or specimen.location ~= "World" or partsById[specimen.id] then
		warn(`[Hollowbound] Refused to place reward {specimen.id}`)
		return false
	end
	spawnWorldPart(specimen, position, false)
	return true
end

function WorldRelics.spawnDropped(specimen, position: Vector3): boolean
	if specimen.ownerUserId ~= nil or specimen.location ~= "World" then
		warn(`[Hollowbound] Refused to drop {specimen.id}: it is owned or not in the world`)
		return false
	end
	if partsById[specimen.id] then
		warn(`[Hollowbound] Refused to drop {specimen.id}: it already has a world part`)
		return false
	end
	spawnWorldPart(specimen, position, true)
	return true
end

-- Available world relics near a point, from the authoritative records: the specimen
-- must be ownerless and in the world, with a live world part. Returns at most
-- maxTargets entries, nearest first: { id, position, name, rarity } (no traits).
function WorldRelics.availableNear(position: Vector3, radius: number, maxTargets: number)
	local found = {}
	for specimenId, part in partsById do
		local specimen = store:get(specimenId)
		if specimen and specimen.ownerUserId == nil and specimen.location == "World" and part.Parent then
			local distance = (part.Position - position).Magnitude
			if distance <= radius then
				table.insert(found, {
					id = specimenId,
					position = part.Position,
					distance = distance,
					name = Config.RelicTypes[specimen.typeId].displayName,
					rarity = specimen.rarity,
				})
			end
		end
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	while #found > maxTargets do
		table.remove(found)
	end
	return found
end

function WorldRelics.folder(): Folder
	return folder
end

function WorldRelics.start(theStore)
	store = theStore

	folder = Instance.new("Folder")
	folder.Name = "HollowboundWorldRelics"
	folder.Parent = workspace

	local spawns: { [string]: BasePart } = {}
	for _, instance in CollectionService:GetTagged(Config.Tags.RelicSpawn) do
		if instance:IsA("BasePart") then
			spawns[instance.Name] = instance
		end
	end

	local rng = Random.new()
	local function makeId()
		return HttpService:GenerateGUID(false)
	end

	for _, entry in Config.TestSpecimens do
		local spawnPart = spawns[entry.spawnName]
		if not spawnPart then
			warn(`[Hollowbound] No part tagged {Config.Tags.RelicSpawn} named {entry.spawnName}; specimen not spawned.`)
			continue
		end
		local specimen = SpecimenFactory.create(entry.typeId, entry.qualityMin, entry.qualityMax, rng, makeId)
		store:add(specimen)
		spawnWorldPart(specimen, spawnPart.Position + Vector3.new(0, spawnPart.Size.Y / 2 + 1.5, 0), false)
		if Config.Dev.LogTraitsToServerOutput then
			print(`[Hollowbound] Generated {specimen.rarity} {RelicStore.fingerprint(specimen)}`)
		end
	end

	ServerNet.onDevRequest(Net.DevPickupRequest, function(player, specimenId)
		WorldRelics.tryPickup(player, specimenId, "dev-remote")
	end)
end

return WorldRelics
