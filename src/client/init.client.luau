--[[
	Hollowbound client entry point (milestone 3).
	The client handles input and presentation only. Pickup, registration, and service
	happen through ProximityPrompts; equip, use, appraise, and activate are requests the
	server validates (Net.RelicAction). Input goes through Actions so keyboard,
	controller, and touch all reach the same handlers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Net"))
local AbilityFx = require(script.AbilityFx)
local Actions = require(script.Actions)
local DevKeys = require(script.DevKeys)
local Hud = require(script.Hud)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Net.FolderName)
local relicAction = remotes:WaitForChild(Net.RelicAction)

local hud

-- Sends one action to the server and shows its answer. Never yields the caller.
local function request(action: string, ...)
	local args = table.pack(...)
	task.spawn(function()
		local ok, result = pcall(function()
			return relicAction:InvokeServer(action, table.unpack(args, 1, args.n))
		end)
		if not ok or typeof(result) ~= "table" then
			hud:toast("The server did not answer. Try again.", "error")
		elseif result.message ~= "" then
			hud:toast(result.message, if result.ok then "success" else "error")
		end
	end)
end

hud = Hud.new(player:WaitForChild("PlayerGui"), request)

for slot = 1, 3 do
	Actions.on(`UseSlot{slot}`, function()
		request("Use", slot)
	end)
end
Actions.on("ToggleRelics", function()
	hud:toggleMenu()
end)
Actions.on("CloseMenu", function()
	hud:setMenuOpen(false)
end)
for _, name in { "UseSlot1", "UseSlot2", "UseSlot3", "ToggleRelics" } do
	Actions.setBound(name, true)
end

remotes:WaitForChild(Net.StateChanged).OnClientEvent:Connect(function(state)
	if typeof(state) == "table" then
		hud:setState(state)
	end
end)

remotes:WaitForChild(Net.Notify).OnClientEvent:Connect(function(text, kind)
	hud:toast(text, kind)
end)

AbilityFx.start(remotes:WaitForChild(Net.AbilityFx))

player:GetAttributeChangedSignal("HB_Zone"):Connect(function()
	hud:setZone(player:GetAttribute("HB_Zone"))
end)
hud:setZone(player:GetAttribute("HB_Zone"))

local initial = remotes:WaitForChild(Net.GetState):InvokeServer()
if typeof(initial) == "table" then
	hud:setState(initial)
end

DevKeys.start(remotes, hud)
