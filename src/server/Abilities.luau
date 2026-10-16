--[[
	Relic abilities (milestone 3, provisional). Server only.

	Windhook ("Gust leap"): a short forward-and-upward push. The server picks the
	direction from the character's facing and caps speed and duration (Config). The client
	sends only the slot number: no positions or directions are accepted, so the request
	cannot teleport or fly. The push is a LinearVelocity with a finite force, so walls and
	ceilings still stop the player. Charges, the cooldown, and "one boost at a time"
	prevent chaining it into flight.

	Echo Lens ("Echo pulse"): marks available world relics near the player, for that
	player only. Targets come from WorldRelics' authoritative records: ownerless relics
	lying in the world. The client gets positions, names, and rarities, never traits.

	Effects that need the relic to stay equipped (the Windhook push, Echo marks) end
	when the relic is unequipped, swapped out, dropped, or its owner dies or leaves.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local AbilityRules = require(script.Parent.AbilityRules)
local Characters = require(script.Parent.Characters)
local Guard = require(script.Parent.Guard)
local RelicDefs = require(script.Parent.RelicDefs)
local RelicView = require(script.Parent.RelicView)
local ServerNet = require(script.Parent.ServerNet)
local WorldRelics = require(script.Parent.WorldRelics)

local Abilities = {}

local store
local sessions
local now: () -> number

local active: { [number]: { [string]: (boolean) -> () } } = {} -- [userId][specimenId] = cleanup(silent)
local boosting: { [number]: boolean } = {}

local function addEffect(userId: number, specimenId: string, cleanup: (boolean) -> ())
	active[userId] = active[userId] or {}
	local previous = active[userId][specimenId]
	if previous then
		previous(true)
	end
	active[userId][specimenId] = cleanup
end

-- silent = the effect ran out on its own (the client already expires it)
local function endEffect(userId: number, specimenId: string, silent: boolean)
	local effects = active[userId]
	local cleanup = effects and effects[specimenId]
	if cleanup then
		effects[specimenId] = nil
		cleanup(silent)
	end
end

function Abilities.endEffectsFor(userId: number, specimenIds: { string })
	for _, specimenId in specimenIds do
		endEffect(userId, specimenId, false)
	end
end

function Abilities.endAll(userId: number)
	local effects = active[userId]
	if not effects then
		return
	end
	for specimenId in effects do
		endEffect(userId, specimenId, false)
	end
	active[userId] = nil
	boosting[userId] = nil
end

local function windhook(player: Player, root: BasePart, specimen, params)
	local userId = player.UserId
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local velocity = flat * params.forwardSpeed + Vector3.new(0, params.upwardSpeed, 0)

	local attachment = Instance.new("Attachment")
	attachment.Name = "HB_WindhookAttachment"
	attachment.Parent = root

	local push = Instance.new("LinearVelocity")
	push.Name = "HB_Windhook"
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	push.VectorVelocity = velocity
	push.MaxForce = params.maxForce
	push.Parent = root

	-- Visible to everyone: a short burst of pale wind particles.
	local gust = Instance.new("ParticleEmitter")
	gust.Name = "HB_WindhookGust"
	gust.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
	gust.Transparency = NumberSequence.new(0.3, 1)
	gust.Size = NumberSequence.new(1.2, 0.2)
	gust.Lifetime = NumberRange.new(0.3, 0.5)
	gust.Speed = NumberRange.new(4, 8)
	gust.SpreadAngle = Vector2.new(30, 30)
	gust.Rate = 80
	gust.LightEmission = 0.6
	gust.Parent = attachment

	boosting[userId] = true
	local finished = false
	addEffect(userId, specimen.id, function()
		if finished then
			return
		end
		finished = true
		push:Destroy()
		attachment:Destroy()
		boosting[userId] = nil
	end)
	task.delay(params.duration, function()
		endEffect(userId, specimen.id, true)
	end)

	ServerNet.abilityFx(player, { kind = "Windhook", duration = params.duration })
	return "Gust leap!"
end

local function echoLens(player: Player, root: BasePart, specimen, params)
	local userId = player.UserId
	local found = WorldRelics.availableNear(root.Position, params.radius, params.maxTargets)
	local targets = {}
	for _, target in found do
		table.insert(targets, {
			id = target.id,
			position = target.position,
			label = `{target.name} ({target.rarity})`,
		})
	end

	addEffect(userId, specimen.id, function(silent)
		if not silent then
			ServerNet.abilityFx(player, { kind = "EchoLensEnd" })
		end
	end)
	task.delay(params.markDuration, function()
		endEffect(userId, specimen.id, true)
	end)

	ServerNet.abilityFx(player, {
		kind = "EchoLens",
		origin = root.Position,
		radius = params.radius,
		duration = params.markDuration,
		targets = targets,
	})
	if #targets == 0 then
		return "Echo pulse: no relics nearby."
	end
	return `Echo pulse: {#targets} relic(s) marked.`
end

local REASONS = {
	BadSlot = "That slot does not exist.",
	SlotEmpty = "That slot is empty.",
	NotFound = "That relic is not available.",
	NotOwner = "That relic is not yours.",
	NotCarried = "You are not carrying that relic.",
	NotEquipped = "Equip the relic first.",
}

-- Returns (ok, message).
function Abilities.use(player: Player, slot: any): (boolean, string)
	local allowed, blocked = Guard.check(player)
	if not allowed then
		return false, blocked :: string
	end
	local root = Characters.liveRoot(player)
	if not root then
		return false, "You cannot use relics while defeated."
	end
	local userId = player.UserId

	-- A boost already in progress blocks another (checked before paying any charge).
	if typeof(slot) == "number" then
		local specimenId = store:equippedIn(userId, slot)
		local specimen = specimenId and store:get(specimenId)
		if specimen and RelicDefs.ability(specimen.typeId) == "Windhook" and boosting[userId] then
			return false, "Already gusting."
		end
	end

	local cooldowns = {
		getDeadline = function(abilityId)
			return sessions:cooldownDeadline(userId, abilityId)
		end,
		setDeadline = function(abilityId, deadline)
			sessions:setCooldown(userId, abilityId, deadline)
		end,
	}
	local ok, reason, specimen, params, remaining = AbilityRules.tryUse(store, cooldowns, userId, slot, now())
	if not ok then
		if reason == "CoolingDown" then
			return false, string.format("Cooling down: %.1f s left.", remaining or 0)
		end
		return false, REASONS[reason :: string] or RelicView.BLOCKERS[reason :: string] or "You cannot use that relic now."
	end

	local message
	if params.abilityId == "Windhook" then
		message = windhook(player, root, specimen, params)
	else
		message = echoLens(player, root, specimen, params)
	end
	sessions:commit(userId, false)
	print(
		string.format(
			"[Hollowbound] %s used %s (%s): %d charge(s) left, cooldown %.1f s",
			player.Name,
			params.abilityId,
			specimen.id,
			specimen.charges,
			params.cooldown
		)
	)
	return true, `{message} {specimen.charges}/{RelicDefs.maxCharges(specimen.typeId)} charges left.`
end

-- nowFn returns unix seconds; cooldown deadlines are saved in the player's profile.
function Abilities.start(theStore, theSessions, nowFn: () -> number)
	store = theStore
	sessions = theSessions
	now = nowFn
	assert(Config.Abilities.Windhook and Config.Abilities.EchoLens, "Ability config missing")
end

return Abilities
