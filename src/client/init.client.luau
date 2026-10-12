--[[
	Hollowbound client entry point (milestone 2).
	The client handles input and presentation only. Pickup, registration, displays, and
	upgrades happen through ProximityPrompts, and rope climbing through requests, all of
	which the server validates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Net"))
local DevKeys = require(script.DevKeys)
local Hud = require(script.Hud)
local DepthVeil = require(script.DepthVeil)
local LayerEffects = require(script.LayerEffects)
local NightEffects = require(script.NightEffects)
local RelicSpin = require(script.RelicSpin)
local RopeController = require(script.RopeController)
local RopePose = require(script.RopePose)
local ShopMenu = require(script.ShopMenu)
local SprintController = require(script.SprintController)
local UpgradeBoards = require(script.UpgradeBoards)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Net.FolderName)

local hud = Hud.new(player:WaitForChild("PlayerGui"))
local slotsUsed = 0

local function refreshStats()
	hud:setStats({
		cash = player:GetAttribute("HB_Cash"),
		income = player:GetAttribute("HB_Income"),
		ropeLength = player:GetAttribute("HB_RopeLength"),
		ropeSpeed = player:GetAttribute("HB_RopeSpeed"),
		slots = player:GetAttribute("HB_Slots"),
		slotsUsed = slotsUsed,
		deepest = player:GetAttribute("HB_Deepest"),
	})
end

local function setInventory(items)
	slotsUsed = 0
	for _, item in items do
		if item.placed then
			slotsUsed += 1
		end
	end
	hud:setInventory(items)
	refreshStats()
end

remotes:WaitForChild(Net.InventoryChanged).OnClientEvent:Connect(setInventory)

remotes:WaitForChild(Net.Notify).OnClientEvent:Connect(function(text, kind)
	hud:toast(text, kind)
end)

remotes:WaitForChild(Net.Announce).OnClientEvent:Connect(function(title, subtitle, rarity)
	hud:announce(title, subtitle, rarity)
end)

local function refreshZone()
	hud:setZone(player:GetAttribute("HB_Zone"), player:GetAttribute("HB_Layer"))
end
player:GetAttributeChangedSignal("HB_Zone"):Connect(refreshZone)
player:GetAttributeChangedSignal("HB_Layer"):Connect(refreshZone)
refreshZone()

for _, name in { "HB_Cash", "HB_Income", "HB_RopeLength", "HB_RopeSpeed", "HB_Slots", "HB_Deepest" } do
	player:GetAttributeChangedSignal(name):Connect(refreshStats)
end
refreshStats()

setInventory(remotes:WaitForChild(Net.GetInventory):InvokeServer())

LayerEffects.start(hud)
RelicSpin.start()

-- Live depth meter: read straight from the character every frame (the server's
-- HB_Depth attribute only updates a few times a second).
RunService.RenderStepped:Connect(function()
	local center = workspace:GetAttribute("HB_HollowCenter")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if typeof(center) == "Vector3" and root and root:IsA("BasePart") then
		hud:setDepth(center.Y - (root.Position.Y - 3)) -- measured at the feet
	end
end)
task.spawn(DepthVeil.start) -- waits for the Hollow's centre
NightEffects.start(hud)
RopeController.start(remotes, hud)
RopePose.start()
SprintController.start(remotes, hud)
ShopMenu.start(remotes)
task.spawn(UpgradeBoards.start, remotes)
DevKeys.start(remotes, hud)
