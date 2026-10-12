--[[
	Sprint input and the stamina bar. Presentation and input only: holding Left Shift
	(or the gamepad's left stick click) tells the server you want to sprint. The server
	(Stamina) decides whether you do, sets your walk speed, and publishes HB_Stamina and
	HB_Sprinting, which the bar shows.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local SprintController = {}

local SPRINT_KEYS = {
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.ButtonL3] = true,
}

function SprintController.start(remotes: Instance, hud)
	local player = Players.LocalPlayer
	local sprintRemote = remotes:WaitForChild(Net.Sprint)
	local wants = false

	local function send(value: boolean)
		if wants ~= value then
			wants = value
			sprintRemote:FireServer(value)
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if SPRINT_KEYS[input.KeyCode] and not processed then
			send(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if SPRINT_KEYS[input.KeyCode] then
			send(false)
		end
	end)
	-- Releasing the key while the window is unfocused would otherwise leave sprint on.
	UserInputService.WindowFocusReleased:Connect(function()
		send(false)
	end)

	local function refresh()
		local stamina = player:GetAttribute("HB_Stamina")
		local fraction = if typeof(stamina) == "number" then stamina / Config.Sprint.MaxStamina else 1
		hud:setStamina(fraction, player:GetAttribute("HB_Sprinting") == true, fraction * Config.Sprint.MaxStamina < Config.Sprint.MinToStart)
	end
	player:GetAttributeChangedSignal("HB_Stamina"):Connect(refresh)
	player:GetAttributeChangedSignal("HB_Sprinting"):Connect(refresh)
	refresh()
end

return SprintController
