--[[
	Provisional configuration (milestones 1-3).

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

-- Proposed examples: both types come from the design record's illustrative catalogue.
-- requiresActivation (Decided: activation varies by relic): the prototype brief chose
-- Windhook = needs town activation, Echo Lens = works immediately after pickup.
-- ability names an entry in Config.Abilities. Trait lists are permanent once rolled;
-- changing them here never rerolls existing specimens.
Config.RelicTypes = {
	Windhook = {
		displayName = "Windhook",
		requiresActivation = true,
		ability = "Windhook",
		traits = {
			{ id = "reach", label = "Reach", unit = "studs", min = 20, max = 60, decimals = 0 },
			{ id = "cargoSupport", label = "Carrying strength", unit = "", min = 0.2, max = 1.0, decimals = 2 },
			{ id = "efficiency", label = "Charge efficiency", unit = "", min = 0.2, max = 1.0, decimals = 2 },
		},
	},
	EchoLens = {
		displayName = "Echo Lens",
		requiresActivation = false,
		ability = "EchoLens",
		traits = {
			{ id = "scanRange", label = "Scan range", unit = "studs", min = 40, max = 120, decimals = 0 },
			{ id = "clarity", label = "Echo clarity", unit = "s", min = 4, max = 10, decimals = 1 },
			{ id = "efficiency", label = "Charge efficiency", unit = "", min = 0.2, max = 1.0, decimals = 2 },
		},
	},
}

--[[
	Provisional abilities (milestone 3 brief). Each tuned value is either a number or
	{ trait = id, worst = a, best = b }: the specimen's trait is normalized to 0..1 within
	its type's min..max and mapped from worst to best. A missing trait uses worst, so an
	older specimen is never given a new roll. Cooldowns are per player and per ability,
	so swapping slots or switching copies never resets them.
]]
Config.Abilities = {
	Windhook = {
		displayName = "Gust leap",
		description = "A short forward-and-upward boost for ledges and escapes.",
		maxCharges = 3,
		cooldown = { trait = "efficiency", worst = 6, best = 3 }, -- seconds
		duration = 0.35, -- seconds the boost pushes
		forwardSpeed = { trait = "reach", worst = 40, best = 70 }, -- studs/s, capped below
		upwardSpeed = { trait = "cargoSupport", worst = 24, best = 38 }, -- studs/s, capped below
		maxForwardSpeed = 80, -- hard caps checked on the server
		maxUpwardSpeed = 45,
		maxForce = 100000, -- LinearVelocity force; finite so geometry still stops the player
	},
	EchoLens = {
		displayName = "Echo pulse",
		description = "Marks nearby relics lying in the world, for you only.",
		maxCharges = 4,
		cooldown = { trait = "efficiency", worst = 12, best = 6 },
		radius = { trait = "scanRange", worst = 40, best = 120 }, -- studs
		markDuration = { trait = "clarity", worst = 4, best = 10 }, -- seconds
		maxTargets = 12,
	},
}

-- Provisional loadout (milestone 3 brief): 3 slots, at most 1 exceptional relic
-- (Decided: one exceptional relic plus support; the slot count is Open). Eligibility
-- maps the existing rarity vocabulary to a slot class. Proposed in the design record:
-- classify by the specimen's actual rarity.
Config.Loadout = {
	Slots = 3,
	ClassByRarity = {
		Common = "Support",
		Uncommon = "Support",
		Rare = "Support",
		Exceptional = "Exceptional",
	},
	MaxPerClass = {
		Exceptional = 1, -- Support has no limit beyond the free slots
	},
}

-- Specimens generated at every server start. spawnName must match a part tagged
-- Tags.RelicSpawn. The non-overlapping quality bands keep A and B's traits apart and
-- make C-E's rarities predictable for tests (D and E are Exceptional).
Config.TestSpecimens = {
	{ typeId = "Windhook", spawnName = "RelicSpawnA", qualityMin = 0.15, qualityMax = 0.33 },
	{ typeId = "Windhook", spawnName = "RelicSpawnB", qualityMin = 0.70, qualityMax = 0.88 },
	{ typeId = "EchoLens", spawnName = "RelicSpawnC", qualityMin = 0.40, qualityMax = 0.60 },
	{ typeId = "EchoLens", spawnName = "RelicSpawnD", qualityMin = 0.92, qualityMax = 0.99 },
	{ typeId = "Windhook", spawnName = "RelicSpawnE", qualityMin = 0.92, qualityMax = 0.99 },
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

-- Town appraisal and activation (Delegated: free appraisal in town; Decided:
-- activation varies by relic). Free for testing; costs are Open. They use the existing
-- registry terminals and service stations: the player must be in a town zone and
-- within ServerMaxDistance of one of them.
Config.TownDesk = {
	ServerMaxDistance = 14,
}

-- Final death (Decided): unregistered relics drop as world pickups; registered relics
-- stay with their owner and return needing service. The downed/revive stage comes later.
Config.Death = {
	-- Open: how damaged a protected relic returns. Placeholder: fully worn and empty.
	ProtectedConditionAfterDeath = 0,
	ProtectedChargesAfterDeath = 0,
	DropScatterRadius = 3, -- studs between multiple dropped relics
	DropHeightAboveGround = 1.5,
	GroundProbeDistance = 60, -- how far below a point to look for ground
	VoidMargin = 50, -- positions this close to FallenPartsDestroyHeight count as "below the map"
	SafePositionSampleInterval = 0.5, -- seconds between recording a grounded position
}

-- Town service (repair/recharge). Decided: it restores usability and never changes traits.
-- It clears Needs service and refills charges to the type's maximum.
-- Open: costs and materials. Free for testing; there is no currency yet, so the server
-- refuses service if Price is above 0.
Config.Service = {
	Price = 0,
	PromptMaxDistance = 10,
	ServerMaxDistance = 14,
	HoldDuration = 0.5,
	RestoredCondition = 1,
}

--[[
	Saving (milestone 3). One ProfileStore profile per UserId, session-locked.
	StoreName is the DataStore name. Use a separate published test experience for real
	persistence checks: DataStores are isolated per experience, so test data never
	touches the live game. Bump the _vN suffix only for a deliberate fresh start.

	StudioMockWhenNoAccess: in Studio without API access, use ProfileStore.Mock on
	purpose and label it MOCK in the HUD and Output (nothing persists). When false, or
	on a live server without DataStore access, loading fails and the player is told to
	rejoin; a blank profile is never used.
]]
Config.Persistence = {
	StoreName = "HollowboundPlayers_v1",
	KeyPrefix = "Player_",
	SchemaVersion = 1,
	StudioMockWhenNoAccess = true,
	AccessWaitTimeout = 15, -- seconds to wait for ProfileStore to learn DataStore access
	SameServerReloadAttempts = 5, -- retries when a rejoin races this server's own session end
}

-- Abuse limits for client requests (equip, use, appraise, activate).
Config.Requests = {
	MaxPerSecond = 8,
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
	BuildRelicFixtures = true, -- add pedestals C-E for the milestone 3 test specimens
	RunSelfTest = true, -- run the logic tests (mock storage only) on server start
	EnableDevRemotes = true, -- create dev remotes for range, race, and repeated-death tests
	LogTraitsToServerOutput = true, -- print hidden traits in server Output (never sent to clients)
	TimedPickupInterval = 5, -- seconds; dev key J fires on the next multiple of this server time
}

return Config
