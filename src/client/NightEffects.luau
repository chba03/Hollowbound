--[[
	The night's look and countdown on this client. Presentation only: the server
	(NightCycle) decides when night falls and sets workspace attributes HB_Night,
	HB_NightAt, and HB_DawnAt. This tweens the local sky to night and back, and keeps the
	HUD's night timer up to date.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))

local NightEffects = {}

local FADE = TweenInfo.new(4, Enum.EasingStyle.Sine)

local function clock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function NightEffects.start(hud)
	-- The day look, as the server set it; restored at dawn.
	local day = {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	}
	local nightLook = {
		ClockTime = Config.Night.ClockTime,
		Brightness = 1,
		Ambient = Color3.fromRGB(40, 44, 70),
		OutdoorAmbient = Color3.fromRGB(60, 66, 100),
	}

	local isNight = false
	local function apply()
		local nowNight = workspace:GetAttribute("HB_Night") == true
		if nowNight == isNight then
			return
		end
		isNight = nowNight
		if isNight then
			-- Capture the day look again in case the server changed it since we started.
			day = {
				ClockTime = Lighting.ClockTime,
				Brightness = Lighting.Brightness,
				Ambient = Lighting.Ambient,
				OutdoorAmbient = Lighting.OutdoorAmbient,
			}
		end
		TweenService:Create(Lighting, FADE, if isNight then nightLook else day):Play()
	end
	workspace:GetAttributeChangedSignal("HB_Night"):Connect(apply)
	apply()

	task.spawn(function()
		while true do
			local t = workspace:GetServerTimeNow()
			if workspace:GetAttribute("HB_Night") == true then
				local dawnAt = workspace:GetAttribute("HB_DawnAt")
				hud:setNightTimer(`Night: dawn in {clock((if typeof(dawnAt) == "number" then dawnAt else t) - t)}`, true)
			else
				local nightAt = workspace:GetAttribute("HB_NightAt")
				local remaining = (if typeof(nightAt) == "number" then nightAt else t) - t
				hud:setNightTimer(`Nightfall in {clock(remaining)}`, remaining <= 60)
			end
			task.wait(0.5)
		end
	end)
end

return NightEffects
