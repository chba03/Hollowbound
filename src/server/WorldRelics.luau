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
local Markers = require(script.Parent.Markers)
local Reach = require(script.Parent.Reach)
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

--[[
	Milestone 5 relic forms (proxies built from engraved stone parts; see docs/ASSETS.md).
	Each world relic is a Model named Relic_<id> whose "Core" part carries the tag,
	SpecimenId, and pickup prompt. Decorative pieces never collide or block raycasts.
	Pieces named HB_Float are animated locally by each client (RelicIdle). A restrained
	glow uses the rarity color; nothing shows traits.
]]
local STONE = Color3.fromRGB(196, 190, 176)
local DARK_STONE = Color3.fromRGB(120, 116, 108)

local function decorPiece(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	if shape then
		p.Shape = shape
	end
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = cframe
	p.Parent = model
	return p
end

local function buildForm(model: Model, base: CFrame, core: BasePart, typeId: string, accent: Color3, glow: number)
	if typeId == "Windhook" then
		-- A curled stone hook with an engraved channel and a floating ring.
		decorPiece(model, "Shank", Vector3.new(0.45, 1.6, 0.45), base * CFrame.new(0, 0.3, 0), STONE, Enum.Material.Slate)
		decorPiece(model, "Curl", Vector3.new(0.4, 0.9, 0.4), base * CFrame.new(0.35, 1.15, 0) * CFrame.Angles(0, 0, math.rad(-50)), STONE, Enum.Material.Slate)
		decorPiece(model, "Tip", Vector3.new(0.35, 0.6, 0.35), base * CFrame.new(0.75, 1.0, 0) * CFrame.Angles(0, 0, math.rad(-130)), DARK_STONE, Enum.Material.Slate)
		decorPiece(model, "Engraving", Vector3.new(0.08, 1.3, 0.47), base * CFrame.new(0, 0.3, 0), accent, Enum.Material.Neon).Transparency = 0.35
		local ring = decorPiece(model, "HB_Float", Vector3.new(0.12, 1.5, 1.5), base * CFrame.new(0, 2.1, 0) * CFrame.Angles(0, 0, math.rad(90)), DARK_STONE, Enum.Material.Slate, Enum.PartType.Cylinder)
		ring:SetAttribute("FloatSpin", 40)
	else
		-- An upright stone disc with a lens and three floating shards.
		decorPiece(model, "Disc", Vector3.new(0.35, 1.6, 1.6), base * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, math.rad(90), 0), STONE, Enum.Material.Slate, Enum.PartType.Cylinder)
		local lens = decorPiece(model, "Lens", Vector3.new(0.7, 0.7, 0.7), base * CFrame.new(0, 0.6, 0), accent, Enum.Material.Glass, Enum.PartType.Ball)
		lens.Transparency = 0.25
		for i = 0, 2 do
			local shard = decorPiece(model, "HB_Float", Vector3.new(0.18, 0.45, 0.12), base * CFrame.new(math.cos(i * 2.09) * 1.2, 0.8, math.sin(i * 2.09) * 1.2), DARK_STONE, Enum.Material.Slate)
			shard:SetAttribute("FloatOrbit", 1.2)
			shard:SetAttribute("FloatPhase", i * 2.09)
		end
	end
	local light = Instance.new("PointLight")
	light.Color = accent
	light.Brightness = glow
	light.Range = 7
	light.Shadows = false
	light.Parent = core
end

local GLOW = { Common = 0.25, Uncommon = 0.35, Rare = 0.5, Exceptional = 0.75 }

local function spawnWorldPart(specimen, position: Vector3, dropped: boolean)
	local relicType = Config.RelicTypes[specimen.typeId]

	local model = Instance.new("Model")
	model.Name = "Relic_" .. specimen.id
	local part = Instance.new("Part")
	part.Name = "Core"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.4, 1.4, 1.4)
	part.Material = Enum.Material.Slate
	part.Color = DARK_STONE
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = CFrame.new(position - Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part:SetAttribute("SpecimenId", specimen.id)
	part.Parent = model
	-- Build upright around the core's position (the core itself lies on its side).
	buildForm(model, CFrame.new(position - Vector3.new(0, 0.9, 0)), part, specimen.typeId, rarityColor(specimen.rarity), GLOW[specimen.rarity] or 0.3)
	model.PrimaryPart = part
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- the prompt and its form stream together
	end)

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
	model.Parent = folder
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

	-- Distance, same level, and a clear line (milestone 5: never through floors).
	local reachable, why = Reach.check(root, part, Config.Pickup.ServerMaxDistance, { part.Parent :: Instance })
	if not reachable then
		local distance = (root.Position - part.Position).Magnitude
		ServerNet.notify(
			player,
			if why == "Far"
				then string.format("Too far away to pick that up (%.0f studs, limit %d).", distance, Config.Pickup.ServerMaxDistance)
				else Reach.message(why),
			"error"
		)
		print(string.format("[Hollowbound] Rejected pickup by %s (%s): %s, distance %.1f", player.Name, source, why or "?", distance))
		return false
	end

	local ok, reason = store:claim(specimenId, player.UserId)
	if not ok then
		ServerNet.notify(player, REJECTIONS[reason :: string] or "You cannot pick that up.", "error")
		print(`[Hollowbound] Rejected pickup by {player.Name} ({source}): {reason}`)
		return false
	end

	partsById[specimenId] = nil
	local holder = part.Parent
	if holder and holder:IsA("Model") and holder.Name == "Relic_" .. specimenId then
		holder:Destroy()
	else
		part:Destroy()
	end

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
	for _, instance in Markers.tagged(Config.Tags.RelicSpawn) do
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
