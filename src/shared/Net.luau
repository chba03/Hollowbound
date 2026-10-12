-- Remote names shared by server and client.
-- The server creates the folder at startup; the client waits for it.

return {
	FolderName = "HollowboundRemotes",

	GetInventory = "GetInventory", -- RemoteFunction: client -> server, returns inventory views
	InventoryChanged = "InventoryChanged", -- RemoteEvent: server -> client, inventory views
	Notify = "Notify", -- RemoteEvent: server -> client, (text, kind)

	-- Studio-only test hook. Only exists when Config.Dev.EnableDevRemotes is on and the
	-- server runs in Studio. Sends a pickup request that skips the prompt's range limit,
	-- so the server's own validation can be tested.
	DevPickupRequest = "DevPickupRequest",
	-- Studio-only test hook. Kills the requesting player's character and calls the death
	-- handler several more times for the same character, to test duplicate protection.
	DevRepeatDeath = "DevRepeatDeath",
}
