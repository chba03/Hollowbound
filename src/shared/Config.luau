--[[
	Provisional configuration (milestones 1-2).

	Design status labels follow docs/Hollowbound_Game_Design_v0_2.pdf:
	  Decided   - explicit design choice
	  Delegated - assistant recommendation adopted as the working direction
	  Proposed  - illustrative example, not selected
	  Open      - still needs a decision or testing
	Every number in this file is a placeholder for testing, not a balance decision.
]]

local Config = {}

-- Open: rarity labels and the rating system are undecided. Placeholder tiers chosen
-- by specimen quality. The design's "two sources of rarity" (type scarcity plus
-- specimen quality) will feed in once relic types have spawn weights.
Config.Rarities = {
	{ id = "Common", minQuality = 0.0, color = Color3.fromRGB(200, 200, 200) },
	{ id = "Uncommon", minQuality = 0.35, color = Color3.fromRGB(110, 200, 120) },
	{ id = "Rare", minQuality = 0.65, color = Color3.fromRGB(90, 150, 255) },
	{ id = "Exceptional", minQuality = 0.9, color = Color3.fromRGB(255, 190, 70) },
}

-- How far each trait may stray from the specimen's overall quality (0..1 scale).
Config.TraitSpread = 0.1

-- Proposed example: "Windhook" comes from the design record's illustrative catalogue.
-- It is used here only as a provisional test type; it has no ability yet.
Config.RelicTypes = {
	Windhook = {
		displayName = "Windhook",
		-- Decided: some relics need activation. Windhook is set to need it so the
		-- separate activation state is visible in the UI. Activation is later work.
		requiresActivation = true,
		-- Permanent traits, rolled once on the server when the specimen is created.
		traits = {
			{ id = "reach", label = "Reach", unit = "studs", min = 20, max = 60, decimals = 0 },
			{ id = "cargoSupport", label = "Carrying strength", unit = "", min = 0.2, max = 1.0, decimals = 2 },
			{ id = "efficiency", label = "Charge efficiency", unit = "", min = 0.2, max = 1.0, decimals = 2 },
		},
	},
}

-- Two test specimens of the same type with non-overlapping quality bands, so their
-- permanent traits always differ. spawnName must match a part tagged Tags.RelicSpawn.
Config.TestSpecimens = {
	{ typeId = "Windhook", spawnName = "RelicSpawnA", qualityMin = 0.15, qualityMax = 0.35 },
	{ typeId = "Windhook", spawnName = "RelicSpawnB", qualityMin = 0.70, qualityMax = 0.95 },
}

Config.Pickup = {
	PromptMaxDistance = 8, -- client-side prompt visibility
	ServerMaxDistance = 12, -- server check; a little slack for latency
	HoldDuration = 0.3,
}

Config.Registration = {
	PromptMaxDistance = 10,
	ServerMaxDistance = 14,
	HoldDuration = 0.5,
}

-- Final death (Decided): unregistered relics drop as world pickups; registered relics
-- stay with their owner and return needing service. The downed/revive stage comes later.
Config.Death = {
	-- Open: how damaged a protected relic returns. Placeholder: fully worn and empty.
	ProtectedConditionAfterDeath = 0,
	ProtectedChargeAfterDeath = 0,
	DropScatterRadius = 3, -- studs between multiple dropped relics
	DropHeightAboveGround = 1.5,
	GroundProbeDistance = 60, -- how far below a point to look for ground
	VoidMargin = 50, -- positions this close to FallenPartsDestroyHeight count as "below the map"
	SafePositionSampleInterval = 0.5, -- seconds between recording a grounded position
}

-- Town service (repair/recharge). Decided: it restores usability and never changes traits.
-- Open: costs and materials. Free for testing; there is no currency yet, so the server
-- refuses service if Price is above 0.
Config.Service = {
	Price = 0,
	PromptMaxDistance = 10,
	ServerMaxDistance = 14,
	HoldDuration = 0.5,
	RestoredCondition = 1,
	RestoredCharge = 1,
}

Config.Zones = {
	CheckInterval = 0.25, -- seconds between server position checks
}

-- CollectionService tags. Hand-built geometry can use these tags instead of the dev map.
Config.Tags = {
	RelicSpawn = "HB_RelicSpawn",
	WorldRelic = "HB_WorldRelic",
	RegistrationTerminal = "HB_RegistrationTerminal",
	ServiceStation = "HB_ServiceStation", -- must stand inside a town zone
	TownZone = "HB_TownZone",
	CampZone = "HB_CampZone",
}

-- Development-only switches. All of these only take effect inside Roblox Studio.
Config.Dev = {
	BuildPlaceholderMap = true, -- build town, camp, and expedition placeholders at runtime
	BuildServiceStation = true, -- add a service station next to the registration terminal if none is tagged
	RunSelfTest = true, -- run the logic self-test on server start
	EnableDevRemotes = true, -- create dev remotes for range, race, and repeated-death tests
	LogTraitsToServerOutput = true, -- print hidden traits in server Output (never sent to clients)
	TimedPickupInterval = 5, -- seconds; dev key J fires on the next multiple of this server time
}

return Config
