--[[
	Layer-based relic spawning in the Hollow.

	Spawn points are BaseParts tagged Tags.RelicSpawn with a Layer attribute (1..7).
	Each layer keeps up to Config.Layers[n].maxNodes relics in the world. Every
	Config.Spawner.TickSeconds, each layer below its cap fills one empty spawn point.

	What spawns comes from that layer's table: a rarity tier rolled by the tier weights
	(Config.Rarities), then that layer's relic of that tier (Config.RelicsByLayer), with a
	specimen quality rolled in the layer's `quality` band. Deeper layers hold better
	relics, and higher tiers are rarer. Decided: a very rare relic has a very low chance of appearing outside
	its usual depth, so a small LuckyChance rolls from a deeper layer's table instead.
	The specimen still records the layer it was found in.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Perks = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Perks"))
local Progression = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Progression"))
local RelicStore = require(script.Parent.RelicStore)
local ServerNet = require(script.Parent.ServerNet)
local SpecimenFactory = require(script.Parent.SpecimenFactory)
local WorldRelics = require(script.Parent.WorldRelics)

local RelicSpawner = {}

local store
local rng = Random.new()
local pointsByLayer: { [number]: { BasePart } } = {}
local occupant: { [BasePart]: string } = {}
local paused = false -- true during the night

local function makeId(): string
	return HttpService:GenerateGUID(false)
end

local function isOccupied(point: BasePart): boolean
	local specimenId = occupant[point]
	if not specimenId then
		return false
	end
	local specimen = store:get(specimenId)
	if specimen and specimen.location == "World" then
		return true
	end
	occupant[point] = nil -- picked up
	return false
end

-- Chooses the table to roll from: usually this layer's, rarely a deeper one.
function RelicSpawner.rollTable(layer: number, random: Random)
	local source = layer
	if random:NextNumber() < Config.Spawner.LuckyChance then
		source = math.min(layer + Config.Spawner.LuckyLayerJump, #Config.Layers)
	end
	return Config.Layers[source], source
end

-- Weighted tier roll. With a layer, only tiers that layer holds can come up (layers
-- 1-2 have no Divine or Godly, 3-4 no Godly). Returns a tier id from Config.Rarities.
-- weights (optional) replaces the tiers' spawn weights, e.g. a crate's odds. Without
-- it, a lit Lucky Lantern (Perks.serverLuckLeft) multiplies the rarer tiers' weights.
function RelicSpawner.rollRarity(random: Random, layer: number?, weights: { [string]: number }?): string
	local byTier = if layer then Config.RelicsByLayer[layer] else nil
	local luck = Config.Shop.ServerLuck
	local lucky = weights == nil and Perks.serverLuckLeft() > 0
	local tiers, tierWeights = {}, {}
	local total = 0
	for _, tier in Config.Rarities do
		if not byTier or byTier[tier.id] then
			local w = if weights then (weights[tier.id] or 0) else tier.weight
			if lucky and tier.rank >= luck.minRank then
				w *= luck.multiplier
			end
			table.insert(tiers, tier)
			table.insert(tierWeights, w)
			total += w
		end
	end
	local roll = random:NextNumber() * total
	for i, tier in tiers do
		roll -= tierWeights[i]
		if roll < 0 then
			return tier.id
		end
	end
	return tiers[1].id
end

-- Picks a relic type from a layer for a tier, falling back to lower tiers if the layer
-- has none of that tier.
function RelicSpawner.pickType(layer: number, rarity: string, random: Random): string
	local byTier = Config.RelicsByLayer[layer]
	for rank = Config.RarityById[rarity].rank, 1, -1 do
		local ids = byTier[Config.Rarities[rank].id]
		if ids and #ids > 0 then
			return ids[random:NextInteger(1, #ids)]
		end
	end
	error(`Layer {layer} has no relic types`)
end

local function spawnOne(layer: number, point: BasePart)
	local tableDef, source = RelicSpawner.rollTable(layer, rng)
	-- The tier comes from the layer the relic lies in, so a lucky roll brings a deeper
	-- layer's relic but never a tier that layer may not hold (no Godly above layer 5).
	local typeId = RelicSpawner.pickType(source, RelicSpawner.rollRarity(rng, layer), rng)
	local specimen =
		SpecimenFactory.create(typeId, tableDef.quality[1], tableDef.quality[2], rng, makeId, layer)
	store:add(specimen)
	WorldRelics.spawn(specimen, point)
	occupant[point] = specimen.id

	if source ~= layer then
		print(`[Hollowbound] Lucky spawn in layer {layer}: rolled from layer {source}`)
	end
	local tier = Config.RarityById[specimen.rarity]
	if tier.rank >= Config.Announce.MinRank then
		local name = Progression.relicName(specimen.typeId, specimen.size)
		ServerNet.announceAll(
			`{string.upper(specimen.rarity)} RELIC SIGHTED`,
			`{name} has appeared in Layer {layer}: {Config.Layers[layer].name}`,
			specimen.rarity
		)
		print(`[Hollowbound] Announced {specimen.rarity} {specimen.typeId} in layer {layer}`)
	end
	if Config.Dev.LogTraitsToServerOutput then
		print(`[Hollowbound] Generated L{layer} {specimen.rarity} {RelicStore.fingerprint(specimen)}`)
	end
end

local function fill(layer: number, maxSpawns: number)
	local points = pointsByLayer[layer]
	local cap = Config.Layers[layer].maxNodes
	local free, active = {}, 0
	for _, point in points do
		if isOccupied(point) then
			active += 1
		elseif point.Parent then
			table.insert(free, point)
		end
	end

	local spawned = 0
	while active < cap and #free > 0 and spawned < maxSpawns do
		local point = table.remove(free, rng:NextInteger(1, #free))
		spawnOne(layer, point)
		active += 1
		spawned += 1
	end
end

-- Night: removes every relic still lying in the Hollow and stops refills until
-- refillAll. Returns how many were removed.
function RelicSpawner.clearAll(): number
	paused = true
	local removed = 0
	for point, specimenId in occupant do
		if WorldRelics.despawn(specimenId) then
			removed += 1
		end
		occupant[point] = nil
	end
	return removed
end

-- Dawn: fills every layer with fresh relics and resumes the normal refills.
function RelicSpawner.refillAll()
	paused = false
	for layer = 1, #Config.Layers do
		fill(layer, math.huge)
	end
end

function RelicSpawner.start(theStore)
	store = theStore

	for layer = 1, #Config.Layers do
		pointsByLayer[layer] = {}
	end
	local total = 0
	for _, instance in CollectionService:GetTagged(Config.Tags.RelicSpawn) do
		local layer = instance:GetAttribute("Layer")
		if instance:IsA("BasePart") and typeof(layer) == "number" and pointsByLayer[layer] then
			table.insert(pointsByLayer[layer], instance)
			total += 1
		end
	end
	print(`[Hollowbound] Relic spawner: {total} spawn points across {#Config.Layers} layers`)

	-- Start every layer full, then refill one relic per layer per tick.
	for layer = 1, #Config.Layers do
		fill(layer, math.huge)
	end
	task.spawn(function()
		while true do
			task.wait(Config.Spawner.TickSeconds)
			if paused then
				continue
			end
			for layer = 1, #Config.Layers do
				fill(layer, 1)
			end
		end
	end)
end

return RelicSpawner
