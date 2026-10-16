--[[
	Expedition lifecycle per player (milestone 4), built on ExpeditionCore. Server only.

	Follows the zone of each living character through Zones.onTick:
	  Town -> leaving starts a run (Exploring or AtCamp) -> back in town finishes it.
	Final death finishes the run through Defeat's final-death hook (exactly once).
	Ending a run never registers, appraises, activates, repairs, or recharges relics.

	Player attributes for the HUD: HB_Phase ("Town" | "Exploring" | "AtCamp"),
	HB_SelfRescuesLeft.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local ExpeditionCore = require(script.Parent.ExpeditionCore)
local ServerNet = require(script.Parent.ServerNet)
local Zones = require(script.Parent.Zones)

local Expedition = {}

local states: { [Player]: any } = {}
local runCounter = 0

local function makeRunId(): number
	runCounter += 1
	return runCounter
end

local function stateFor(player: Player)
	local state = states[player]
	if not state then
		state = ExpeditionCore.new()
		states[player] = state
	end
	return state
end

local function publish(player: Player, state)
	if player.Parent then
		player:SetAttribute("HB_Phase", state.phase)
		player:SetAttribute("HB_SelfRescuesLeft", ExpeditionCore.selfRescuesLeft(state, Config.SelfRescue.PerExpedition))
	end
end

function Expedition.update(player: Player, zone: string)
	local state = stateFor(player)
	local events = ExpeditionCore.onZone(state, zone, os.clock(), makeRunId)
	for _, event in events do
		if event.kind == "RunStarted" then
			print(`[Hollowbound] {player.Name} started expedition run {event.runId}`)
			ServerNet.notify(player, "Expedition started. Camps are refuges; only town secures relics.", "info")
		elseif event.kind == "RunFinished" then
			print(`[Hollowbound] {player.Name} finished run {event.runId} ({event.reason})`)
			ServerNet.notify(player, "Back in town. Register new relics at the terminal to secure them.", "success")
		end
	end
	if #events > 0 then
		publish(player, state)
	end
end

-- Final death or a forced end. Safe to call repeatedly; only the first call ends a run.
function Expedition.finishRun(player: Player, reason: string)
	local state = states[player]
	if not state then
		return
	end
	local runId = ExpeditionCore.finish(state)
	if runId then
		print(`[Hollowbound] {player.Name} finished run {runId} ({reason})`)
		publish(player, state)
	end
end

function Expedition.phase(player: Player): string
	local state = states[player]
	return if state then state.phase else "Town"
end

function Expedition.runId(player: Player): number?
	local state = states[player]
	return state and ExpeditionCore.runId(state)
end

function Expedition.selfRescuesLeft(player: Player): number
	local state = states[player]
	return if state then ExpeditionCore.selfRescuesLeft(state, Config.SelfRescue.PerExpedition) else 0
end

-- Spends one self-rescue of the given run. Returns false for a stale run or no allowance.
function Expedition.useSelfRescue(player: Player, runId: number): boolean
	local state = states[player]
	if not state then
		return false
	end
	local ok = ExpeditionCore.useSelfRescue(state, runId, Config.SelfRescue.PerExpedition)
	if ok then
		publish(player, state)
	end
	return ok
end

function Expedition.start()
	Zones.onTick(function(player, zone)
		Expedition.update(player, zone)
	end)
	Players.PlayerRemoving:Connect(function(player)
		task.defer(function()
			states[player] = nil
		end)
	end)
end

return Expedition
