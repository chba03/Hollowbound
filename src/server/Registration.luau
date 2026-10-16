--[[
	Town registration terminal. Any BasePart tagged Tags.RegistrationTerminal gets a
	prompt. Place terminals only in town: only a return to town secures relics (Decided).

	Registration changes only the existing record's `registered` flag. It never copies
	a specimen, issues a new ID, or touches traits, appraisal, or activation.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Characters = require(script.Parent.Characters)
local Guard = require(script.Parent.Guard)
local Markers = require(script.Parent.Markers)
local Reach = require(script.Parent.Reach)
local RelicStore = require(script.Parent.RelicStore)
local ServerNet = require(script.Parent.ServerNet)

local Registration = {}

local store
local sessions

local function describe(specimens): string
	local names = {}
	for _, specimen in specimens do
		table.insert(names, `{Config.RelicTypes[specimen.typeId].displayName} ({specimen.rarity})`)
	end
	return table.concat(names, ", ")
end

function Registration.tryRegister(player: Player, terminal: BasePart)
	local allowed, blocked = Guard.checkActive(player)
	if not allowed then
		ServerNet.notify(player, blocked :: string, "error")
		return
	end
	local root = Characters.liveRoot(player)
	if not root then
		return
	end
	local reachable, why = Reach.check(root, terminal, Config.Registration.ServerMaxDistance)
	if not reachable then
		ServerNet.notify(player, if why == "Far" then "Move closer to the terminal." else Reach.message(why), "error")
		return
	end

	local carried = store:carried(player.UserId)
	if #carried == 0 then
		ServerNet.notify(player, "You are not carrying any relics.", "info")
		return
	end

	-- Registration changes only `registered`: not traits, service, charges, appraisal,
	-- or activation.
	local function snapshot(specimen)
		return `{RelicStore.fingerprint(specimen)}|{specimen.needsService}|{specimen.charges}|{specimen.appraised}|{specimen.activated}`
	end
	local before = {}
	for _, specimen in carried do
		before[specimen.id] = snapshot(specimen)
	end

	local newly, already = store:registerCarried(player.UserId)

	-- Guard: registration must never change identity or traits.
	for _, specimen in store:carried(player.UserId) do
		assert(
			snapshot(specimen) == before[specimen.id],
			"Registration changed specimen identity or state: " .. specimen.id
		)
	end
	assert(#store:carried(player.UserId) == #carried, "Registration changed the number of carried relics")

	if #newly > 0 then
		-- Registration itself is complete now. Saving is separate: the HUD's save badge
		-- shows "Saving..." until storage confirms.
		sessions:commit(player.UserId, true)
		ServerNet.notify(player, `Registered: {describe(newly)}. Secured in town.`, "success")
	else
		ServerNet.notify(player, `Nothing new to register. Already registered: {describe(already)}.`, "info")
	end
	ServerNet.pushState(player)

	for _, specimen in newly do
		print(`[Hollowbound] {player.Name} registered {RelicStore.fingerprint(specimen)}`)
	end
	if #already > 0 then
		print(`[Hollowbound] {player.Name} re-used terminal; {#already} already registered, no changes`)
	end
end

local function attach(terminal: Instance)
	if not terminal:IsA("BasePart") then
		warn(`[Hollowbound] {terminal:GetFullName()} is tagged as a terminal but is not a BasePart.`)
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Register relics"
	prompt.ObjectText = "Registry Terminal"
	prompt.MaxActivationDistance = Config.Registration.PromptMaxDistance
	prompt.HoldDuration = Config.Registration.HoldDuration
	prompt.RequiresLineOfSight = false
	prompt.Parent = terminal
	prompt.Triggered:Connect(function(player)
		Registration.tryRegister(player, terminal)
	end)
end

function Registration.start(theStore, theSessions)
	store = theStore
	sessions = theSessions
	for _, terminal in Markers.tagged(Config.Tags.RegistrationTerminal) do
		attach(terminal)
	end
	Markers.onAdded(Config.Tags.RegistrationTerminal, attach)
end

return Registration
