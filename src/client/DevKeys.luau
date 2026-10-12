--[[
	DEVELOPMENT ONLY (Studio). Keys that send pickup requests through the dev remote,
	so you can test the server's checks:
	  K - request the nearest world relic now, ignoring the prompt's range.
	      Use it far away to test rejection of out-of-range pickups.
	  J - request the nearest world relic on the next shared server-time boundary.
	      Press J in both client windows within a few seconds of each other. Both
	      requests then fire at the same moment, testing a simultaneous pickup.
	The server applies the same validation as a prompt pickup.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local DevKeys = {}

local function nearestRelic(): (string?, number?)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil, nil
	end
	local bestId, bestDistance = nil, math.huge
	for _, part in CollectionService:GetTagged(Config.Tags.WorldRelic) do
		if part:IsA("BasePart") then
			local distance = (part.Position - root.Position).Magnitude
			if distance < bestDistance then
				bestId, bestDistance = part:GetAttribute("SpecimenId"), distance
			end
		end
	end
	return bestId, if bestId then bestDistance else nil
end

function DevKeys.start(remotes: Instance, hud)
	if not RunService:IsStudio() then
		return
	end
	local remote = remotes:FindFirstChild(Net.DevPickupRequest)
	if not remote then
		return
	end

	hud:showDevHint("DEV  K: pickup request ignoring prompt range   J: timed pickup (race test)")

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode ~= Enum.KeyCode.K and input.KeyCode ~= Enum.KeyCode.J then
			return
		end

		local specimenId, distance = nearestRelic()
		if not specimenId then
			hud:toast("Dev: no relics left in the world.", "info")
			return
		end

		if input.KeyCode == Enum.KeyCode.K then
			hud:toast(
				string.format("Dev: requesting pickup from %.0f studs (server limit %d).", distance, Config.Pickup.ServerMaxDistance),
				"info"
			)
			remote:FireServer(specimenId)
		else
			local interval = Config.Dev.TimedPickupInterval
			local now = workspace:GetServerTimeNow()
			local fireAt = (math.floor(now / interval) + 1) * interval
			hud:toast(string.format("Dev: timed pickup fires in %.1f s (server time %d).", fireAt - now, fireAt), "info")
			task.delay(fireAt - now, function()
				remote:FireServer(specimenId)
			end)
		end
	end)
end

return DevKeys
