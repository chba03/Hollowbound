--[[
	Spawns the test specimens in the expedition area and handles pickup.

	Pickup requests come from the server-side ProximityPrompt.Triggered event, or, in
	Studio, from the dev remote. Both use tryPickup, which checks the character,
	distance, availability, and ownership before claiming.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Characters = require(script.Parent.Characters)
local RelicStore = require(script.Parent.RelicStore)
local ServerNet = require(script.Parent.ServerNet)
local SpecimenFactory = require(script.Parent.SpecimenFactory)

local WorldRelics = {}

local store
local partsById: { [string]: BasePart } = {}

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

local function spawnWorldPart(specimen, spawnPart: BasePart, folder: Folder)
	local relicType = Config.RelicTypes[specimen.typeId]

	local part = Instance.new("Part")
	part.Name = "Relic_" .. specimen.id
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.6, 1.6, 1.6)
	part.Material = Enum.Material.Neon
	part.Color = rarityColor(specimen.rarity)
	part.Anchored = true
	part.CanCollide = false
	part.Position = spawnPart.Position + Vector3.new(0, spawnPart.Size.Y / 2 + 1.5, 0)
	part:SetAttribute("SpecimenId", specimen.id)

	-- The prompt only shows type and rarity, which are visible before appraisal.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = `{relicType.displayName} ({specimen.rarity})`
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
	ServerNet.pushInventory(player)
	print(`[Hollowbound] {player.Name} picked up {specimenId} via {source}`)
	return true
end

function WorldRelics.start(theStore)
	store = theStore

	local folder = Instance.new("Folder")
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
		spawnWorldPart(specimen, spawnPart, folder)
		if Config.Dev.LogTraitsToServerOutput then
			print(`[Hollowbound] Generated {specimen.rarity} {RelicStore.fingerprint(specimen)}`)
		end
	end

	ServerNet.onDevPickupRequest(function(player, specimenId)
		WorldRelics.tryPickup(player, specimenId, "dev-remote")
	end)
end

return WorldRelics
