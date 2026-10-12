--[[
	Town service station (repair/recharge). Any BasePart tagged Tags.ServiceStation gets
	a prompt. The station clears Needs service on relics its user carries.

	The server checks that the player is alive, inside a town zone, and near the
	station, and that each relic is owned, carried, and needs service. Service restores
	condition and charge only. It never changes ID, traits, registration, appraisal, or
	activation, and never creates a new record.

	Cost: Open. Service is free for testing (Config.Service.Price = 0). There is no
	currency yet, so a nonzero price makes the server refuse service.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Characters = require(script.Parent.Characters)
local RelicStore = require(script.Parent.RelicStore)
local ServerNet = require(script.Parent.ServerNet)
local Zones = require(script.Parent.Zones)

local ServiceStation = {}

local store

local REJECTIONS = {
	NotFound = "relic not found",
	NotOwner = "not your relic",
	NotCarried = "not carried",
	NotNeeded = "already serviced",
}

function ServiceStation.tryService(player: Player, station: BasePart)
	local root = Characters.liveRoot(player)
	if not root then
		return
	end
	if Zones.zoneAt(root.Position) ~= "Town" then
		ServerNet.notify(player, "Relic service is only available in town.", "error")
		return
	end
	if (root.Position - station.Position).Magnitude > Config.Service.ServerMaxDistance then
		ServerNet.notify(player, "Move closer to the service station.", "error")
		return
	end
	if Config.Service.Price > 0 then
		ServerNet.notify(player, "Paid service is not implemented yet.", "error")
		return
	end

	local carried = store:carried(player.UserId)
	local before = {}
	local candidates = {}
	for _, specimen in carried do
		before[specimen.id] = RelicStore.identityAndStates(specimen)
		if specimen.needsService then
			table.insert(candidates, specimen)
		end
	end
	if #candidates == 0 then
		ServerNet.notify(player, "None of your relics need service.", "info")
		return
	end

	local names = {}
	for _, specimen in candidates do
		local ok, reason = store:service(
			player.UserId,
			specimen.id,
			Config.Service.RestoredCondition,
			Config.Service.RestoredCharge
		)
		if ok then
			table.insert(names, `{Config.RelicTypes[specimen.typeId].displayName} ({specimen.rarity})`)
			print(`[Hollowbound] {player.Name} serviced {RelicStore.identityAndStates(specimen)}`)
		else
			print(`[Hollowbound] Service refused for {player.Name} on {specimen.id}: {REJECTIONS[reason :: string] or reason}`)
		end
	end

	-- Guard: service must never change identity, traits, or the other states, and must
	-- never add or remove relics.
	local after = store:carried(player.UserId)
	assert(#after == #carried, "Service changed the number of carried relics")
	for _, specimen in after do
		assert(RelicStore.identityAndStates(specimen) == before[specimen.id], "Service changed relic " .. specimen.id)
	end

	if #names > 0 then
		ServerNet.notify(player, `Serviced: {table.concat(names, ", ")}. Condition and charge restored.`, "success")
	end
	ServerNet.pushInventory(player)
end

local function attach(station: Instance)
	if not station:IsA("BasePart") then
		warn(`[Hollowbound] {station:GetFullName()} is tagged as a service station but is not a BasePart.`)
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Service relics"
	prompt.ObjectText = "Relic Service"
	prompt.MaxActivationDistance = Config.Service.PromptMaxDistance
	prompt.HoldDuration = Config.Service.HoldDuration
	prompt.RequiresLineOfSight = false
	prompt.Parent = station
	prompt.Triggered:Connect(function(player)
		ServiceStation.tryService(player, station)
	end)
end

function ServiceStation.start(theStore)
	store = theStore
	for _, station in CollectionService:GetTagged(Config.Tags.ServiceStation) do
		attach(station)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.ServiceStation):Connect(attach)
end

return ServiceStation
