--[[
	Hollowbound server entry point (milestone 2).
	The server owns specimen generation, inventories, ownership, registration, plots,
	displays, income, upgrades, rope state, and saved data.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Admin = require(script.Admin)
local Arsenal = require(script.Arsenal)
local Ascent = require(script.Ascent)
local BaseManager = require(script.BaseManager)
local DevMap = require(script.DevMap)
local Enemies = require(script.Enemies)
local FallDamage = require(script.FallDamage)
local Grapple = require(script.Grapple)
local Hauling = require(script.Hauling)
local Hollow = require(script.Hollow)
local NightCycle = require(script.NightCycle)
local PlayerData = require(script.PlayerData)
local Plots = require(script.Plots)
local Registration = require(script.Registration)
local RelicMarks = require(script.RelicMarks)
local RelicSpawner = require(script.RelicSpawner)
local RelicStore = require(script.RelicStore)
local RopeService = require(script.RopeService)
local SelfTest = require(script.SelfTest)
local Stamina = require(script.Stamina)
local Store = require(script.Store)
local ServerNet = require(script.ServerNet)
local WorldRelics = require(script.WorldRelics)
local Zones = require(script.Zones)

local inStudio = RunService:IsStudio()

if inStudio and Config.Dev.RunSelfTest then
	SelfTest.run()
end

-- Build the dev map first so plots, the rim, and spawn points exist. Live servers build
-- it too unless Config.Dev.BuildMapOnLiveServers is off (a baked map is kept as is).
if Config.Dev.BuildPlaceholderMap and (inStudio or Config.Dev.BuildMapOnLiveServers) then
	local ok, err = pcall(DevMap.ensure)
	if not ok then
		warn("[Hollowbound] Dev map build failed: " .. tostring(err))
	end
end
Hollow.start()

local store = RelicStore.new()
ServerNet.start(store)
Plots.start() -- before PlayerData, so plots are assigned while data loads
PlayerData.start(store)
WorldRelics.start(store)
RelicSpawner.start(store)
Registration.start(store)
BaseManager.start(store)
Store.start(store)
RopeService.start()
Stamina.start()
Hauling.start()
Arsenal.start()
Grapple.start()
Enemies.start()
FallDamage.start()
Zones.start(store)
NightCycle.start()
Ascent.start(store)
RelicMarks.start(store)
Admin.start()

print("[Hollowbound] Milestone 2 server ready.")
