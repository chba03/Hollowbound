--[[
	Creates the remotes and sends inventory and notification updates to clients.
	Clients never send state changes. They only ask for their inventory and, in Studio,
	send dev requests, which go through the normal server code paths.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local RelicView = require(script.Parent.RelicView)

local ServerNet = {}

local store
local remotes = {}

local function make(className: string, name: string, parent: Instance)
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	remotes[name] = remote
	return remote
end

function ServerNet.start(theStore)
	store = theStore

	local folder = Instance.new("Folder")
	folder.Name = Net.FolderName
	make("RemoteFunction", Net.GetInventory, folder)
	make("RemoteEvent", Net.InventoryChanged, folder)
	make("RemoteEvent", Net.Notify, folder)
	if Config.Dev.EnableDevRemotes and RunService:IsStudio() then
		make("RemoteEvent", Net.DevPickupRequest, folder)
		make("RemoteEvent", Net.DevRepeatDeath, folder)
	end
	folder.Parent = ReplicatedStorage

	remotes[Net.GetInventory].OnServerInvoke = function(player)
		return ServerNet.inventoryView(player)
	end
end

function ServerNet.inventoryView(player: Player)
	local views = {}
	for _, specimen in store:carried(player.UserId) do
		table.insert(views, RelicView.forOwner(specimen))
	end
	return views
end

function ServerNet.pushInventory(player: Player)
	remotes[Net.InventoryChanged]:FireClient(player, ServerNet.inventoryView(player))
end

-- kind: "info" | "success" | "error"
function ServerNet.notify(player: Player, text: string, kind: string?)
	remotes[Net.Notify]:FireClient(player, text, kind or "info")
end

-- Connects a handler to a Studio-only dev remote. Does nothing outside Studio.
function ServerNet.onDevRequest(remoteName: string, handler: (Player, any) -> ())
	local remote = remotes[remoteName]
	if remote then
		remote.OnServerEvent:Connect(handler)
	end
end

return ServerNet
