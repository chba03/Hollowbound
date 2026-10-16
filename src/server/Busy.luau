--[[
	Server-timed actions per player (bandaging, reviving, self-rescue), built on BusyCore.
	One action at a time per player; each re-validates every frame and completes only by
	the server clock. The HUD reads the player attributes HB_Action and HB_ActionEndsAt
	(server time) for a progress bar.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BusyCore = require(script.Parent.BusyCore)

local Busy = {}

local core = BusyCore.new()

local function setAttributes(player: Player, kind: string?, endsAt: number?)
	if player.Parent then
		player:SetAttribute("HB_Action", kind)
		player:SetAttribute("HB_ActionEndsAt", endsAt)
	end
end

function Busy.kind(player: Player): string?
	return BusyCore.kind(core, player)
end

--[[
	spec = { kind, duration, interruptible, validate, complete, cancelled } (see BusyCore).
	Returns (token) or (nil, "Busy").
]]
function Busy.begin(player: Player, spec): (number?, string?)
	local complete, cancelled = spec.complete, spec.cancelled
	local wrapped = table.clone(spec)
	wrapped.complete = function()
		setAttributes(player, nil, nil)
		complete()
	end
	wrapped.cancelled = function(reason)
		setAttributes(player, nil, nil)
		if cancelled then
			cancelled(reason)
		end
	end
	local token, reason = BusyCore.begin(core, player, wrapped, os.clock())
	if token then
		setAttributes(player, spec.kind, workspace:GetServerTimeNow() + spec.duration)
	end
	return token, reason
end

function Busy.cancel(player: Player, reason: string): boolean
	return BusyCore.cancel(core, player, reason)
end

-- Cancels interruptible actions (bandage, self-rescue) when the player takes damage.
function Busy.interrupt(player: Player, reason: string): boolean
	return BusyCore.interrupt(core, player, reason)
end

function Busy.start()
	RunService.Heartbeat:Connect(function()
		BusyCore.step(core, os.clock())
	end)
	Players.PlayerRemoving:Connect(function(player)
		BusyCore.cancel(core, player, "Left")
	end)
end

return Busy
