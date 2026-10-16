--[[
	Creates the remotes and sends state and notification updates to clients.
	Clients never send state changes directly. They ask for their state, send action
	requests (RelicAction), and, in Studio, dev requests; the server validates all of it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local ServerNet = {}

local remotes = {}
local buildState: ((Player) -> any)? = nil

local function make(className: string, name: string, parent: Instance)
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	remotes[name] = remote
	return remote
end

-- builder(player) returns the player's state table (RelicView.state).
function ServerNet.start(builder: (Player) -> any)
	buildState = builder

	local folder = Instance.new("Folder")
	folder.Name = Net.FolderName
	make("RemoteFunction", Net.GetState, folder)
	make("RemoteEvent", Net.StateChanged, folder)
	make("RemoteEvent", Net.Notify, folder)
	make("RemoteFunction", Net.RelicAction, folder)
	make("RemoteEvent", Net.AbilityFx, folder)
	make("RemoteFunction", Net.FieldAction, folder)
	make("RemoteEvent", Net.CombatFx, folder)
	if Config.Dev.EnableDevRemotes and RunService:IsStudio() then
		make("RemoteEvent", Net.DevPickupRequest, folder)
		make("RemoteEvent", Net.DevRepeatDeath, folder)
	end
	folder.Parent = ReplicatedStorage

	remotes[Net.GetState].OnServerInvoke = function(player)
		return buildState and buildState(player)
	end
end

function ServerNet.pushState(player: Player)
	if buildState and player.Parent then
		remotes[Net.StateChanged]:FireClient(player, buildState(player))
	end
end

-- Older name kept for callers from milestones 1-2.
ServerNet.pushInventory = ServerNet.pushState

-- kind: "info" | "success" | "error"
function ServerNet.notify(player: Player, text: string, kind: string?)
	if player.Parent then
		remotes[Net.Notify]:FireClient(player, text, kind or "info")
	end
end

function ServerNet.abilityFx(player: Player, payload)
	if player.Parent then
		remotes[Net.AbilityFx]:FireClient(player, payload)
	end
end

function ServerNet.combatFx(player: Player, payload)
	if player.Parent then
		remotes[Net.CombatFx]:FireClient(player, payload)
	end
end

-- handler(player, action) -> (ok: boolean, message: string). Extra arguments are dropped.
function ServerNet.onFieldAction(handler)
	remotes[Net.FieldAction].OnServerInvoke = function(player, action)
		local ok, message = handler(player, action)
		return { ok = ok == true, message = message or "" }
	end
end

-- handler(player, action, ...) -> (ok: boolean, message: string)
function ServerNet.onRelicAction(handler)
	remotes[Net.RelicAction].OnServerInvoke = function(player, action, ...)
		local ok, message = handler(player, action, ...)
		return { ok = ok == true, message = message or "" }
	end
end

-- Connects a handler to a Studio-only dev remote. Does nothing outside Studio.
function ServerNet.onDevRequest(remoteName: string, handler: (Player, any) -> ())
	local remote = remotes[remoteName]
	if remote then
		remote.OnServerEvent:Connect(handler)
	end
end

return ServerNet
