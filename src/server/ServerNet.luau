--[[
	Creates the remotes and sends inventory and notification updates to clients.
	Clients never send state changes directly. They ask for their inventory, request a
	rope grab or release (validated by RopeService), and, in Studio, use the dev remotes,
	which go through the normal server validation.
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
	make("RemoteEvent", Net.Announce, folder)
	make("RemoteEvent", Net.RopeGrab, folder)
	make("RemoteEvent", Net.RopeRelease, folder)
	make("RemoteEvent", Net.Sprint, folder)
	make("RemoteEvent", Net.BuyUpgrade, folder)
	make("RemoteEvent", Net.ShopBuy, folder)
	if Config.Dev.EnableDevRemotes and RunService:IsStudio() then
		make("RemoteEvent", Net.DevPickupRequest, folder)
		make("RemoteEvent", Net.DevGrantCash, folder)
	end
	folder.Parent = ReplicatedStorage

	remotes[Net.GetInventory].OnServerInvoke = function(player)
		return ServerNet.inventoryView(player)
	end
end

-- Everything the player owns: pack first, then displayed relics.
function ServerNet.inventoryView(player: Player)
	local views, displayed = {}, {}
	for _, specimen in store:owned(player.UserId) do
		local view = RelicView.forOwner(specimen)
		table.insert(if view.placed then displayed else views, view)
	end
	table.move(displayed, 1, #displayed, #views + 1, views)
	return views
end

function ServerNet.pushInventory(player: Player)
	remotes[Net.InventoryChanged]:FireClient(player, ServerNet.inventoryView(player))
end

-- kind: "info" | "success" | "error"
function ServerNet.notify(player: Player, text: string, kind: string?)
	remotes[Net.Notify]:FireClient(player, text, kind or "info")
end

-- A big message on every player's screen. rarity (a tier id) colours it.
function ServerNet.announceAll(title: string, subtitle: string, rarity: string?)
	remotes[Net.Announce]:FireAllClients(title, subtitle, rarity)
end

-- Connects a handler to a client -> server remote. Dev remotes may not exist.
function ServerNet.on(name: string, handler: (Player, ...any) -> ())
	local remote = remotes[name]
	if remote then
		remote.OnServerEvent:Connect(handler)
	end
end

function ServerNet.onDevPickupRequest(handler: (Player, any) -> ())
	ServerNet.on(Net.DevPickupRequest, handler)
end

return ServerNet
