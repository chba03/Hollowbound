--[[
	Hollowbound server entry point (milestone 2).
	The server owns specimen generation, inventories, ownership, registration, final
	death, and service.
	All state lives in server memory; persistence comes in a later milestone.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Defeat = require(script.Defeat)
local DevMap = require(script.DevMap)
local Registration = require(script.Registration)
local RelicStore = require(script.RelicStore)
local SelfTest = require(script.SelfTest)
local ServerNet = require(script.ServerNet)
local ServiceStation = require(script.ServiceStation)
local WorldRelics = require(script.WorldRelics)
local Zones = require(script.Zones)

local inStudio = RunService:IsStudio()

if inStudio and Config.Dev.RunSelfTest then
	SelfTest.run()
end

-- Build the dev map before WorldRelics so the relic spawn parts exist.
if inStudio and Config.Dev.BuildPlaceholderMap then
	DevMap.ensure()
end
if inStudio and Config.Dev.BuildServiceStation then
	DevMap.ensureServiceStation()
end

local store = RelicStore.new()
ServerNet.start(store)
WorldRelics.start(store)
Registration.start(store)
Zones.start(store)
ServiceStation.start(store)
Defeat.start(store)

print("[Hollowbound] Milestone 2 server ready.")
