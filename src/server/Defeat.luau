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

	Milestone 4: combat and creature damage first downs a character (Vitals); final death
	happens only when the engine kills it (bleedout, Reset Character, the void) or the
	field-departure rule applies. All of those reach this path exactly once per character.
	Final-death hooks then drop ordinary supplies and finish the expedition run.

	TEMPORARY departure rule (private prototype, milestone 3; NOT the final reconnect
	design, which will add reconnect bodies and camp pause/resume):
	  - Leaving outside town applies the final-death rules once, before cleanup.
	  - Leaving in town keeps registered relics as they are. Unregistered relics cannot
	    be saved, so they are released into the world where the player stood.
	  - A known whole-server shutdown applies no penalties: Sessions saves everyone as is.
	  - A lost session (profile taken by another server) applies no penalties: its
	    registered relics already left this server; unregistered ones are released.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Abilities = require(script.Parent.Abilities)
local Guard = require(script.Parent.Guard)
local RelicStore = require(script.Parent.RelicStore)
local ServerNet = require(script.Parent.ServerNet)
local WorldRelics = require(script.Parent.WorldRelics)

local Defeat = {}

local store
local finalDeathHooks: { (Player, Vector3) -> () } = {}
local departedPlayers: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
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

--[[
	fn(player, groundPoint) runs once per final death, after relics are handled, with a
	safe ground point near where it happened (the same placement logic as relic drops).
	Milestone 4 uses it to drop ordinary supplies and to finish the expedition run.
]]
function Defeat.onFinalDeath(fn: (Player, Vector3) -> ())
	table.insert(finalDeathHooks, fn)
end

local function placeInWorld(player: Player, specimens, position: Vector3?, verb: string)
	if #specimens == 0 then
		return
	end
	local center, method = dropCenter(player, position)
	local positions = dropPositions(center, #specimens)
	for i, specimen in specimens do
		WorldRelics.spawnDropped(specimen, positions[i])
		print(`[Hollowbound] {player.Name} {verb} {RelicStore.identityAndStates(specimen)} at {method}`)
	end
end

-- The final-death rules for one player. Shared by character death and the temporary
-- field-departure rule. Does not yield, so no pickup can run in the middle of it.
-- saveNow: request an immediate save (a death in play). A departure skips it because
-- ending the session saves right after.
local function applyFinalDeath(player: Player, position: Vector3?, source: string, saveNow: boolean)
	local before = {}
	for _, specimen in store:carried(player.UserId) do
		before[specimen.id] = RelicStore.identityAndStates(specimen)
	end

	local dropped, protected, unequipped = store:processDeath(
		player.UserId,
		Config.Death.ProtectedConditionAfterDeath,
		Config.Death.ProtectedChargesAfterDeath
	)
	Abilities.endEffectsFor(player.UserId, unequipped)
	Abilities.endAll(player.UserId)

	-- Guard: death must never change identity, traits, or the separate states.
	for _, specimen in dropped do
		assert(RelicStore.identityAndStates(specimen) == before[specimen.id], "Death changed dropped relic " .. specimen.id)
	end
	for _, specimen in protected do
		assert(RelicStore.identityAndStates(specimen) == before[specimen.id], "Death changed protected relic " .. specimen.id)
	end

	placeInWorld(player, dropped, position, "dropped")
	-- Protected relics changed (Needs service): save now so rejoining cannot dodge it.
	local sessions = Guard.sessions()
	if sessions and #protected > 0 then
		sessions:commit(player.UserId, saveNow)
	end
	for _, specimen in protected do
		print(`[Hollowbound] {player.Name} kept registered {specimen.id}; needs service`)
	end
	print(`[Hollowbound] Final death of {player.Name} ({source}): {#dropped} dropped, {#protected} protected`)

	local ground = dropCenter(player, position)
	for _, hook in finalDeathHooks do
		local ok, err = pcall(hook, player, ground + Vector3.new(0, Config.Death.DropHeightAboveGround, 0))
		if not ok then
			warn(`[Hollowbound] Final-death hook failed: {err}`)
		end
	end

	if #dropped > 0 then
		ServerNet.notify(player, `You dropped: {describe(dropped)}. Unregistered relics can be recovered by anyone.`, "error")
	end
	ServerNet.pushState(player)
end

-- Returns true if this call processed the death, or false for a duplicate.
function Defeat.handleDeath(player: Player, character: Model, source: string): boolean
	if handledCharacters[character] then
		print(`[Hollowbound] Ignored duplicate death for {player.Name} ({source})`)
		return false
	end
	handledCharacters[character] = true

	local root = character:FindFirstChild("HumanoidRootPart")
	local deathPosition = if root and root:IsA("BasePart") then root.Position else nil
	applyFinalDeath(player, deathPosition, source, true)
	return true
end

--[[
	Temporary departure rule, applied once per player before Sessions saves and cleans up.
	mode: "Field" (left outside town), "Town", "Shutdown", "Lost" (session taken by
	another server), or "NotLoaded" (left before the profile loaded).
]]
function Defeat.handleDeparture(player: Player, mode: string)
	if departedPlayers[player] then
		return
	end
	departedPlayers[player] = true

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart") then root.Position else nil
	local alreadyDead = character ~= nil and handledCharacters[character] == true

	if mode == "Field" then
		if alreadyDead then
			-- This character's final death was already applied; do not apply it twice.
			print(`[Hollowbound] {player.Name} left while defeated; death already applied`)
		else
			if character then
				handledCharacters[character] = true
			end
			applyFinalDeath(player, position, "left outside town", false)
		end
	elseif mode ~= "Shutdown" then
		local released, unequipped = store:releaseUnregistered(player.UserId)
		Abilities.endEffectsFor(player.UserId, unequipped)
		placeInWorld(player, released, position, "left behind")
		print(`[Hollowbound] {player.Name} left ({mode}): {#released} unregistered relic(s) released, no penalties`)
	else
		print(`[Hollowbound] {player.Name} left during shutdown: saved as is, no penalties`)
	end
	Abilities.endAll(player.UserId)
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
	ServerNet.pushState(player)
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
		-- Deferred: the departure rule still needs the last safe position.
		task.defer(function()
			lastSafePosition[player] = nil
		end)
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
