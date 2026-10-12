--[[
	The night cycle (project owner's brief). Every Config.Night.CycleSeconds night falls:

	  - Every relic still lying in the Hollow fades (RelicSpawner.clearAll) and no new
	    ones appear until dawn.
	  - Every player in the Hollow who is not inside a camp is pulled back to their base.
	    During the night this repeats every SweepInterval, so going back in sends you
	    straight home. Players in town or in a camp's ring stay where they are.
	  - After Config.Night.NightSeconds, dawn refills every layer with fresh relics.

	Unsecured relics stay with the player who carries them; the night only moves people.
	Warnings go to everyone before nightfall. Clients read the workspace attributes
	HB_Night (bool), HB_NightAt and HB_DawnAt (server times, workspace:GetServerTimeNow)
	for the sky and the countdown (client NightEffects).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Characters = require(script.Parent.Characters)
local Plots = require(script.Parent.Plots)
local RelicSpawner = require(script.Parent.RelicSpawner)
local RopeService = require(script.Parent.RopeService)
local ServerNet = require(script.Parent.ServerNet)
local Zones = require(script.Parent.Zones)

local NightCycle = {}

local night = false

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Sends everyone in the Hollow, outside a camp, back to their base. Returns the count.
local function sweep(): number
	local moved = 0
	for _, player in Players:GetPlayers() do
		local root = Characters.liveRoot(player)
		if not root or not Plots.get(player) then
			continue
		end
		local zone = Zones.zoneAt(root.Position)
		if zone == "Depths" then
			RopeService.detach(player)
			Plots.sendHome(player)
			ServerNet.notify(player, "Night fell while you were in the Hollow. You were pulled back to your base.", "info")
			moved += 1
		end
	end
	return moved
end

local function nightfall()
	night = true
	workspace:SetAttribute("HB_Night", true)
	workspace:SetAttribute("HB_DawnAt", now() + Config.Night.NightSeconds)
	local removed = RelicSpawner.clearAll()
	local moved = sweep()
	ServerNet.announceAll("NIGHT FALLS", "The Hollow's relics fade. Anyone outside a camp is pulled back to base.", nil)
	print(`[Hollowbound] Nightfall: {removed} relic(s) faded, {moved} player(s) sent home`)
end

local function dawn()
	night = false
	workspace:SetAttribute("HB_Night", false)
	workspace:SetAttribute("HB_NightAt", now() + Config.Night.CycleSeconds - Config.Night.NightSeconds)
	RelicSpawner.refillAll()
	ServerNet.announceAll("DAWN", "Fresh relics have appeared in every layer of the Hollow.", nil)
	print("[Hollowbound] Dawn: the Hollow refilled")
end

function NightCycle.isNight(): boolean
	return night
end

function NightCycle.start()
	local cfg = Config.Night
	workspace:SetAttribute("HB_Night", false)
	workspace:SetAttribute("HB_NightAt", now() + cfg.CycleSeconds - cfg.NightSeconds)

	task.spawn(function()
		local warned: { [number]: boolean } = {}
		local lastSweep = 0
		while true do
			task.wait(0.25)
			local t = now()
			if night then
				if t >= (workspace:GetAttribute("HB_DawnAt") or 0) then
					dawn()
					warned = {}
				elseif t - lastSweep >= cfg.SweepInterval then
					lastSweep = t
					sweep()
				end
			else
				local remaining = (workspace:GetAttribute("HB_NightAt") or t) - t
				for _, seconds in cfg.Warnings do
					if remaining <= seconds and not warned[seconds] then
						warned[seconds] = true
						for _, player in Players:GetPlayers() do
							ServerNet.notify(player, `Night falls in {seconds} seconds. Get back to your base or into a camp's yellow ring.`, "error")
						end
					end
				end
				if remaining <= 0 then
					nightfall()
					lastSweep = t
				end
			end
		end
	end)
end

return NightCycle
