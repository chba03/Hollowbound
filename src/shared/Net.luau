-- Remote names shared by server and client.
-- The server creates the folder at startup; the client waits for it.

return {
	FolderName = "HollowboundRemotes",

	GetInventory = "GetInventory", -- RemoteFunction: client -> server, returns inventory views
	InventoryChanged = "InventoryChanged", -- RemoteEvent: server -> client, inventory views
	Notify = "Notify", -- RemoteEvent: server -> client, (text, kind)
	Announce = "Announce", -- RemoteEvent: server -> all clients, (title, subtitle, rarity?)

	-- Rope requests. The server validates both and owns the HB_OnRope attribute.
	RopeGrab = "RopeGrab", -- RemoteEvent: client -> server, no arguments
	RopeRelease = "RopeRelease", -- RemoteEvent: client -> server, (atTop: boolean)
	Sprint = "Sprint", -- RemoteEvent: client -> server, (wantsToSprint: boolean)
	ForgeBuy = "ForgeBuy", -- RemoteEvent: client -> server, (pickaxeId)
	ForgeEquip = "ForgeEquip", -- RemoteEvent: client -> server, (pickaxeId)
	HitShown = "HitShown", -- RemoteEvent: server -> client, (position, damage) for damage numbers
	Knockback = "Knockback", -- RemoteEvent: server -> client, (velocity, seconds): you were hit, ragdoll
	HaulStop = "HaulStop", -- RemoteEvent: client -> server, let go of the Hauling Rig
	ShopBuy = "ShopBuy", -- RemoteEvent: client -> server, (itemId: string from Config.Shop.Items)
	BuyUpgrade = "BuyUpgrade", -- RemoteEvent: client -> server, (kind: "RopeLength" | "RopeSpeed" | "BaseSlots")

	-- Studio-only test hooks. Only exist when Config.Dev.EnableDevRemotes is on and the
	-- server runs in Studio. They go through the normal server validation.
	DevPickupRequest = "DevPickupRequest", -- (specimenId) pickup that skips the prompt's range
	DevGrantCash = "DevGrantCash", -- adds Config.Dev.CashGrant
}
