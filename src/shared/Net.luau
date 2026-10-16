-- Remote names shared by server and client.
-- The server creates the folder at startup; the client waits for it.

return {
	FolderName = "HollowboundRemotes",

	GetState = "GetState", -- RemoteFunction: client -> server, returns the player's relic state
	StateChanged = "StateChanged", -- RemoteEvent: server -> client, relic state (see RelicView.state)
	Notify = "Notify", -- RemoteEvent: server -> client, (text, kind)

	-- RemoteFunction: client -> server, (action, ...) -> { ok, message }.
	-- Actions: "Equip"(specimenId, slot), "Unequip"(slot), "Use"(slot),
	-- "Appraise"(specimenId), "Activate"(specimenId). The server validates everything.
	RelicAction = "RelicAction",

	-- RemoteEvent: server -> one client, ability feedback for that player only.
	AbilityFx = "AbilityFx",

	-- Studio-only test hook. Only exists when Config.Dev.EnableDevRemotes is on and the
	-- server runs in Studio. Sends a pickup request that skips the prompt's range limit,
	-- so the server's own validation can be tested.
	DevPickupRequest = "DevPickupRequest",
	-- Studio-only test hook. Kills the requesting player's character and calls the death
	-- handler several more times for the same character, to test duplicate protection.
	DevRepeatDeath = "DevRepeatDeath",
}
