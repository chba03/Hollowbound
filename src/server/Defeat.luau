--[[
	Final death (Decided rules, milestone 2).

	When a character dies:
	  - Unregistered relics leave the player's inventory and become world pickups at a
	    reachable spot. Their ID, traits, appraisal, and activation stay the same, and
	    their previous ownership is cleared.
	  - Registered relics stay owned and carried and are marked Needs service. They are
	    never placed in the world.

	Every character is processed at most once, however many times its death is
	reported. Respawning creates a new character, which is watched separately.

	Later milestones: the designed downed/revive stage (a defeated player can be revived
	or use a self-rescue item before final death), ordinary carried gear, body looting,
	and disconnect rules. For now, any character death counts as final death, including
	Studio's Reset Character. Leaving the game does not drop relics, because disconnect
	rules are Open.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local RelicStore = require(script.Parent.RelicStore)
local ServerNet = require(script.Parent.ServerNet)
local WorldRelics = require(script.Parent.WorldRelics)

local Defeat = {}

local store
local handledCharacters: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lastSafePosition: { [Player]: Vector3 } = {}

local function aboveVoid(position: Vector3): boolean
	return position.Y > workspace.FallenPartsDestroyHeight + Config.Death.VoidMargin
end

-- Finds solid ground under a point, ignoring characters and world relics.
local function groundBelow(position: Vector3): Vector3?
	local exclude: { Instance } = { WorldRelics.folder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude

	local origin = position + Vector3.new(0, 3, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -Config.Death.GroundProbeDistance, 0), params)
	if result and result.Instance:IsA("BasePart") and result.Instance.CanCollide then
		return result.Position
	end
	return nil
end

-- Picks where dropped relics land: the death spot if there is ground under it,
-- otherwise the player's last grounded position, otherwise their respawn point.
local function dropCenter(player: Player, deathPosition: Vector3?): (Vector3, string)
	if deathPosition and aboveVoid(deathPosition) then
		local ground = groundBelow(deathPosition)
		if ground then
			return ground, "death position"
		end
	end
	local safe = lastSafePosition[player]
	if safe then
		return groundBelow(safe) or safe, "last safe position"
	end
	local spawn = player.RespawnLocation
	if spawn then
		return spawn.Position + Vector3.new(0, spawn.Size.Y / 2, 0), "respawn location"
	end
	warn(`[Hollowbound] No valid drop position for {player.Name}; using world origin`)
	return Vector3.new(0, 5, 0), "world origin"
end

local function dropPositions(center: Vector3, count: number): { Vector3 }
	local positions = {}
	local lift = Vector3.new(0, Config.Death.DropHeightAboveGround, 0)
	for i = 1, count do
		local spot = center
		if count > 1 then
			local angle = (i / count) * math.pi * 2
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.Death.DropScatterRadius
			spot = groundBelow(center + offset) or center
		end
		table.insert(positions, spot + lift)
	end
	return positions
end

local function describe(specimens): string
	local names = {}
	for _, specimen in specimens do
		table.insert(names, `{Config.RelicTypes[specimen.typeId].displayName} ({specimen.rarity})`)
	end
	return table.concat(names, ", ")
end

-- Returns true if this call processed the death, or false for a duplicate.
-- Does not yield, so no pickup can run in the middle of it.
function Defeat.handleDeath(player: Player, character: Model, source: string): boolean
	if handledCharacters[character] then
		print(`[Hollowbound] Ignored duplicate death for {player.Name} ({source})`)
		return false
	end
	handledCharacters[character] = true

	local root = character:FindFirstChild("HumanoidRootPart")
	local deathPosition = if root and root:IsA("BasePart") then root.Position else nil

	local before = {}
	for _, specimen in store:carried(player.UserId) do
		before[specimen.id] = RelicStore.identityAndStates(specimen)
	end

	local dropped, protected = store:processDeath(
		player.UserId,
		Config.Death.ProtectedConditionAfterDeath,
		Config.Death.ProtectedChargeAfterDeath
	)

	-- Guard: death must never change identity, traits, or the separate states.
	for _, specimen in dropped do
		assert(RelicStore.identityAndStates(specimen) == before[specimen.id], "Death changed dropped relic " .. specimen.id)
	end
	for _, specimen in protected do
		assert(RelicStore.identityAndStates(specimen) == before[specimen.id], "Death changed protected relic " .. specimen.id)
	end

	if #dropped > 0 then
		local center, method = dropCenter(player, deathPosition)
		local positions = dropPositions(center, #dropped)
		for i, specimen in dropped do
			WorldRelics.spawnDropped(specimen, positions[i])
			print(`[Hollowbound] {player.Name} dropped {RelicStore.identityAndStates(specimen)} at {method}`)
		end
	end
	for _, specimen in protected do
		print(`[Hollowbound] {player.Name} kept registered {specimen.id}; needs service`)
	end
	print(`[Hollowbound] Final death of {player.Name} ({source}): {#dropped} dropped, {#protected} protected`)

	if #dropped > 0 then
		ServerNet.notify(player, `You dropped: {describe(dropped)}. Unregistered relics can be recovered by anyone.`, "error")
	end
	ServerNet.pushInventory(player)
	return true
end

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Died:Connect(function()
		Defeat.handleDeath(player, character, "Humanoid.Died")
	end)

	-- Respawn: protected relics are still in the inventory.
	ServerNet.pushInventory(player)
	local waiting = 0
	for _, specimen in store:carried(player.UserId) do
		if specimen.needsService then
			waiting += 1
		end
	end
	if waiting > 0 then
		ServerNet.notify(player, `{waiting} registered relic(s) returned with you. They need service in town.`, "info")
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
end

-- Studio only: kill the character, then report its death twice more directly.
local function devRepeatDeath(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	humanoid.Health = 0
	Defeat.handleDeath(player, character, "dev repeat 1")
	Defeat.handleDeath(player, character, "dev repeat 2")
end

function Defeat.start(theStore)
	store = theStore

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSafePosition[player] = nil
	end)

	-- Record a recent grounded position, used when a player dies below the map.
	task.spawn(function()
		while true do
			task.wait(Config.Death.SafePositionSampleInterval)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if
					humanoid
					and root
					and root:IsA("BasePart")
					and humanoid.Health > 0
					and humanoid.FloorMaterial ~= Enum.Material.Air
					and aboveVoid(root.Position)
				then
					lastSafePosition[player] = root.Position
				end
			end
		end
	end)

	ServerNet.onDevRequest(Net.DevRepeatDeath, devRepeatDeath)
end

return Defeat
