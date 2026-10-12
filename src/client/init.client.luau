--[[
	Hollowbound client entry point (milestone 1).
	The client handles input and presentation only. Pickup and registration happen
	through ProximityPrompts, which the server validates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Net"))
local DevKeys = require(script.DevKeys)
local Hud = require(script.Hud)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Net.FolderName)

local hud = Hud.new(player:WaitForChild("PlayerGui"))

remotes:WaitForChild(Net.InventoryChanged).OnClientEvent:Connect(function(items)
	hud:setInventory(items)
end)

remotes:WaitForChild(Net.Notify).OnClientEvent:Connect(function(text, kind)
	hud:toast(text, kind)
end)

player:GetAttributeChangedSignal("HB_Zone"):Connect(function()
	hud:setZone(player:GetAttribute("HB_Zone"))
end)
hud:setZone(player:GetAttribute("HB_Zone"))

hud:setInventory(remotes:WaitForChild(Net.GetInventory):InvokeServer())

DevKeys.start(remotes, hud)
