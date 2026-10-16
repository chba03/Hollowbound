--[[
	Central damage interface and character condition (milestone 4). Server only.

	Vitals.damagePlayer is the only way the new combat and creatures hurt a player:
	  - It refuses damage inside protected zones (town, camps).
	  - It never lets the engine kill: reaching 0 health downs the character (Downed),
	    with crawling movement and a bleedout timer.
	  - Bleedout makes the engine kill the character; from there the existing final-death
	    path (Defeat, via Humanoid.Died) runs exactly once, as it does for Reset Character,
	    the void, and any other engine death.
	Any engine death marks the record Dead immediately, so no revivable corpse is left.

	Passive regeneration is explicit: Roblox's default "Health" regeneration script is
	removed, and Config.Health.RegenPerSecond heals by zone (none while exploring).

	Every character gets a unique charId, and every down a new downToken (VitalsCore).
	Callbacks capture them, so a delayed revive or bleedout from an old character or an
	old down does nothing.

	Player attributes for the HUD: HB_Condition, HB_BleedoutAt (server time).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Busy = require(script.Parent.Busy)
local Characters = require(script.Parent.Characters)
local Guard = require(script.Parent.Guard)
local VitalsCore = require(script.Parent.VitalsCore)
local Zones = require(script.Parent.Zones)

local Vitals = {}

local records: { [Player]: any } = {}
local charCounter = 0
local listeners = { downed = {}, revived = {}, dead = {}, hurt = {} }

local DOWN_CFG = {
	healthWhileDowned = Config.Downed.HealthWhileDowned,
	bleedoutSeconds = Config.Downed.BleedoutSeconds,
}

local function fire(list, ...)
	for _, fn in list do
		task.spawn(fn, ...)
	end
end

-- fn(player, record) after a character is downed (record.core.downToken is the down).
function Vitals.onDowned(fn)
	table.insert(listeners.downed, fn)
end
-- fn(player, record) after a revive or self-rescue.
function Vitals.onRevived(fn)
	table.insert(listeners.revived, fn)
end
-- fn(player, record) when the engine killed the character (final death follows).
function Vitals.onDead(fn)
	table.insert(listeners.dead, fn)
end
-- fn(player, amount, source) after damage that did not down.
function Vitals.onHurt(fn)
	table.insert(listeners.hurt, fn)
end

function Vitals.record(player: Player)
	return records[player]
end

-- "Alive" | "Downed" | "Dead" (no character counts as Dead).
function Vitals.condition(player: Player): string
	local record = records[player]
	return if record then record.core.condition else "Dead"
end

function Vitals.charId(player: Player): number?
	local record = records[player]
	return record and record.core.charId
end

local function setAttributes(player: Player, record)
	if not player.Parent then
		return
	end
	player:SetAttribute("HB_Condition", record.core.condition)
	player:SetAttribute(
		"HB_BleedoutAt",
		if record.core.condition == "Downed"
			then workspace:GetServerTimeNow() + (record.core.bleedoutAt - os.clock())
			else nil
	)
end

local function applyHealth(record)
	local humanoid = record.humanoid
	if humanoid.Parent and humanoid.Health > 0 then
		record.writing = true
		humanoid.Health = record.core.health
		record.writing = false
	end
end

local function setDownedMovement(record, downed: boolean)
	local humanoid = record.humanoid
	if downed then
		record.saved = { walk = humanoid.WalkSpeed, jumpPower = humanoid.JumpPower, jumpHeight = humanoid.JumpHeight }
		humanoid.WalkSpeed = Config.Downed.CrawlSpeed
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	elseif record.saved then
		humanoid.WalkSpeed = record.saved.walk
		humanoid.JumpPower = record.saved.jumpPower
		humanoid.JumpHeight = record.saved.jumpHeight
		record.saved = nil
	end
end

--[[
	The central damage interface. Returns ("Hurt" | "Downed" | "Refused", reason?).
	source = { kind = "Creature" | ..., name = string }
	Player-to-player damage is refused while Config.Combat.PlayerVsPlayer is false;
	callers pass source.kind = "Player" for player attacks.
]]
function Vitals.damagePlayer(player: Player, amount: any, source): (string, string?)
	local record = records[player]
	if not record then
		return "Refused", "NoCharacter"
	end
	if source and source.kind == "Player" and not Config.Combat.PlayerVsPlayer then
		return "Refused", "PvPDisabled"
	end
	local root = Characters.liveRoot(player)
	if not root then
		return "Refused", "NoCharacter"
	end
	-- Town and camps protect against combat and creature damage. Falls are environmental
	-- (milestone 5) and still apply there.
	local environmental = source ~= nil and source.kind == "Fall"
	if Zones.isProtected(root.Position) and not environmental then
		return "Refused", "Protected"
	end
	local result, reason = VitalsCore.damage(record.core, amount, os.clock(), DOWN_CFG)
	if result == "Refused" then
		return result, reason
	end
	Busy.interrupt(player, "You were hit.")
	if result == "Hurt" then
		applyHealth(record)
		fire(listeners.hurt, player, amount, source)
	else
		Busy.cancel(player, "You went down.")
		applyHealth(record)
		setDownedMovement(record, true)
		setAttributes(player, record)
		print(`[Hollowbound] {player.Name} was downed by {source and source.name or "damage"} (char {record.core.charId}, down {record.core.downToken})`)
		fire(listeners.downed, player, record)
	end
	return result, nil
end

-- Heals an Alive character. Returns the amount healed.
function Vitals.heal(player: Player, amount: number): number
	local record = records[player]
	if not record then
		return 0
	end
	local healed = VitalsCore.heal(record.core, amount)
	if healed > 0 then
		applyHealth(record)
	end
	return healed
end

-- Brings a Downed character back. charId and token must match the down being revived.
function Vitals.revive(player: Player, charId: number, token: number, health: number, by: string): boolean
	local record = records[player]
	if not record or record.core.charId ~= charId then
		return false
	end
	local ok = VitalsCore.revive(record.core, charId, token, health)
	if not ok then
		return false
	end
	setDownedMovement(record, false)
	applyHealth(record)
	setAttributes(player, record)
	print(`[Hollowbound] {player.Name} was revived by {by} (char {charId}, down {token})`)
	fire(listeners.revived, player, record)
	return true
end

-- Ends a down through the engine so final death runs on the existing path.
local function bleedOut(player: Player, record)
	if record.bleedingOut then
		return
	end
	record.bleedingOut = true
	print(`[Hollowbound] {player.Name} bled out (char {record.core.charId}, down {record.core.downToken})`)
	local humanoid = record.humanoid
	if humanoid.Parent then
		humanoid.Health = 0
	end
	-- Safety net: if the engine did not register the death, break the character.
	task.delay(1, function()
		if records[player] == record and record.core.condition ~= "Dead" and record.character.Parent then
			record.character:BreakJoints()
		end
	end)
end

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or player.Character ~= character then
		return
	end
	charCounter += 1
	local record = {
		core = VitalsCore.new(charCounter, Config.Health.Max),
		character = character,
		humanoid = humanoid,
		writing = false,
	}
	records[player] = record
	humanoid.MaxHealth = Config.Health.Max
	humanoid.Health = Config.Health.Max
	setAttributes(player, record)

	if Config.Health.DisableDefaultRegen then
		task.spawn(function()
			local regen = character:WaitForChild("Health", 5)
			if regen and regen:IsA("Script") then
				regen:Destroy()
			end
		end)
	end

	-- Other engine damage (not through this interface) keeps the record in step.
	humanoid.HealthChanged:Connect(function(newHealth)
		if record.writing or record.core.condition ~= "Alive" then
			return
		end
		if newHealth > 0 and newHealth < record.core.health then
			record.core.health = newHealth
			record.core.lastDamagedAt = os.clock()
		end
	end)

	humanoid.Died:Connect(function()
		if VitalsCore.markDead(record.core) then
			Busy.cancel(player, "You died.")
			setAttributes(player, record)
			fire(listeners.dead, player, record)
		end
	end)
end

local function regenerate(dt: number)
	for player, record in records do
		if record.core.condition ~= "Alive" then
			continue
		end
		local root = Characters.liveRoot(player)
		if not root then
			continue
		end
		local rate = Config.Health.RegenPerSecond[Zones.zoneAt(root.Position)] or 0
		if rate > 0 and os.clock() - record.core.lastDamagedAt >= Config.Health.RegenDelayAfterDamage then
			if VitalsCore.heal(record.core, rate * dt) > 0 then
				applyHealth(record)
			end
		end
	end
end

function Vitals.start()
	Guard.setConditionProvider(Vitals.condition)

	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- Deferred so the departure rule can still read the condition.
		task.defer(function()
			records[player] = nil
		end)
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local now = os.clock()
			for player, record in records do
				if record.core.condition == "Downed" and VitalsCore.bleedoutDue(record.core, record.core.downToken, now) then
					bleedOut(player, record)
				end
			end
			regenerate(now - last)
			last = now
		end
	end)
end

return Vitals
