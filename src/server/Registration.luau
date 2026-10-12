--[[
	Town registration terminal. Any BasePart tagged Tags.RegistrationTerminal gets a
	prompt. Place terminals only in town: only a return to town secures relics (Decided).
	Each rim plot has one, since the plots are the town.

	Registration changes only the existing record's `registered` flag. It never copies
	a specimen, issues a new ID, or touches traits, appraisal, or activation. Newly
	registered relics are then written to the player's saved profile.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Progression = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Progression"))
local Characters = require(script.Parent.Characters)
local PlayerData = require(script.Parent.PlayerData)
local RelicStore = require(script.Parent.RelicStore)
local ServerNet = require(script.Parent.ServerNet)

local Registration = {}

local store

local function describe(specimens): string
	local names = {}
	for _, specimen in specimens do
		table.insert(names, `{Progression.relicName(specimen.typeId, specimen.size)} ({specimen.rarity})`)
	end
	return table.concat(names, ", ")
end

function Registration.tryRegister(player: Player, terminal: BasePart)
	local root = Characters.liveRoot(player)
	if not root then
		return
	end
	if (root.Position - terminal.Position).Magnitude > Config.Registration.ServerMaxDistance then
		ServerNet.notify(player, "Move closer to the terminal.", "error")
		return
	end

	local carried = store:carried(player.UserId)
	if #carried == 0 then
		ServerNet.notify(player, "You are not carrying any relics.", "info")
		return
	end

	local before = {}
	for _, specimen in carried do
		before[specimen.id] = RelicStore.fingerprint(specimen)
	end

	local newly, already = store:registerCarried(player.UserId)

	-- Guard: registration must never change identity or traits.
	for _, specimen in store:carried(player.UserId) do
		assert(
			RelicStore.fingerprint(specimen) == before[specimen.id],
			"Registration changed specimen identity: " .. specimen.id
		)
	end
	assert(#store:carried(player.UserId) == #carried, "Registration changed the number of carried relics")

	for _, specimen in newly do
		PlayerData.saveSpecimen(player, specimen)
	end

	if #newly > 0 then
		ServerNet.notify(player, `Registered: {describe(newly)}. These relics are now secured. Display them on a pedestal to earn cash.`, "success")
	else
		ServerNet.notify(player, `Nothing new to register. Already registered: {describe(already)}.`, "info")
	end
	ServerNet.pushInventory(player)

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

function Registration.start(theStore)
	store = theStore
	for _, terminal in CollectionService:GetTagged(Config.Tags.RegistrationTerminal) do
		attach(terminal)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.RegistrationTerminal):Connect(attach)
end

return Registration
