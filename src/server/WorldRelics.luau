--[[
	Relics lying in the Hollow: the model each one shows (RelicModels), and pickup.

	RelicSpawner decides what spawns where and calls WorldRelics.spawn. Pickup requests
	come from the server-side ProximityPrompt.Triggered event, or, in Studio, from the
	dev remote. Both use tryPickup, which checks the character, distance, availability,
	and ownership before claiming.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Progression = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Progression"))
local Characters = require(script.Parent.Characters)
local Ground = require(script.Parent.Ground)
local RelicModels = require(script.Parent.RelicModels)
local ServerNet = require(script.Parent.ServerNet)

local WorldRelics = {}

local store
local folder: Folder
local partsById: { [string]: BasePart } = {} -- each relic model's Core part
local rng = Random.new()

local REJECTIONS = {
	NotFound = "That relic does not exist.",
	AlreadyOwned = "Someone else picked that relic up first.",
	Unavailable = "That relic is no longer there.",
}

-- Shows a specimen (already added to the store) as its relic model above spawnPart.
function WorldRelics.spawn(specimen, spawnPart: BasePart)
	local tier = Config.RarityById[specimen.rarity]
	local size = math.min(specimen.size or 1, Config.Sizes.MaxWorldScale)
	-- Sit on the real ground under the spawn point (terrain is uneven and grass covers
	-- low objects), with the model's lower half plus some clearance above it.
	local groundY = Ground.below(spawnPart.Position) or (spawnPart.Position.Y + spawnPart.Size.Y / 2)
	local height = 1.1 * (if tier then tier.scale else 1) * size + Config.Pickup.GroundClearance
	local position = Vector3.new(spawnPart.Position.X, groundY + height, spawnPart.Position.Z)
	local cframe = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)

	local model = RelicModels.build(specimen.typeId, specimen.rarity, cframe, true, size)
	model.Name = "Relic_" .. specimen.id
	local core = model.PrimaryPart :: BasePart
	core:SetAttribute("SpecimenId", specimen.id)

	-- The prompt only shows type and rarity, which are visible before appraisal.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = `{Progression.relicName(specimen.typeId, specimen.size)} ({specimen.rarity}) · {Progression.formatCash(Progression.incomeOf(specimen))}/s`
	prompt.MaxActivationDistance = Config.Pickup.PromptMaxDistance + height
	prompt.HoldDuration = Config.Pickup.HoldDuration
	prompt.RequiresLineOfSight = false
	prompt.Parent = core
	prompt.Triggered:Connect(function(player)
		WorldRelics.tryPickup(player, specimen.id, "prompt")
	end)

	CollectionService:AddTag(core, Config.Tags.WorldRelic)
	model.Parent = folder
	partsById[specimen.id] = core
end

-- Removes an unclaimed relic from the world and the store (the night reset).
-- Returns true if it was still there.
function WorldRelics.despawn(specimenId: string): boolean
	if not store:removeWorld(specimenId) then
		return false
	end
	local part = partsById[specimenId]
	partsById[specimenId] = nil
	if part and part.Parent then
		(part.Parent :: Instance):Destroy()
	end
	return true
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
	local limit = Config.Pickup.ServerMaxDistance + part.Size.Y / 2 -- big relics sit higher
	if distance > limit then
		ServerNet.notify(
			player,
			string.format("Too far away to pick that up (%.0f studs, limit %.0f).", distance, limit),
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
	if part.Parent then
		(part.Parent :: Instance):Destroy() -- the whole relic model
	end

	local specimen = store:get(specimenId)
	local name = Progression.relicName(specimen.typeId, specimen.size)
	ServerNet.notify(
		player,
		`Picked up {name} ({specimen.rarity}). Unsecured until registered at your base's terminal.`,
		"success"
	)
	ServerNet.pushInventory(player)
	print(`[Hollowbound] {player.Name} picked up {specimenId} via {source}`)
	return true
end

function WorldRelics.start(theStore)
	store = theStore

	folder = Instance.new("Folder")
	folder.Name = "HollowboundWorldRelics"
	folder.Parent = workspace

	ServerNet.onDevPickupRequest(function(player, specimenId)
		WorldRelics.tryPickup(player, specimenId, "dev-remote")
	end)
end

return WorldRelics
