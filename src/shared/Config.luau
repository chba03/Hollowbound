--[[
	Provisional configuration (milestones 1-4).

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

-- Abuse limits for client requests (relic actions and combat actions).
Config.Requests = {
	MaxPerSecond = 8,
}

--[[
	Milestone 4: the first dangerous PvE expedition. Everything below is provisional
	tuning for testing (Open), unless a line says otherwise.
]]

-- Health. Passive regeneration is explicit and zone-based: none while exploring, so
-- bandages and rescue matter; resting is possible in town and (slowly) at camps
-- (Decided: camps offer rest; exact effects Open). Roblox's default regeneration script
-- is removed from characters so it cannot quietly heal explorers.
Config.Health = {
	Max = 100,
	DisableDefaultRegen = true,
	RegenPerSecond = { Town = 10, Camp = 2, Depths = 0 },
	RegenDelayAfterDamage = 6, -- seconds without damage before zone regeneration starts
}

-- Downed stage (Decided: a defeated player is downed before final death; exact window,
-- costs, and health Open). Damage through the central interface downs instead of kills.
Config.Downed = {
	BleedoutSeconds = 30,
	HealthWhileDowned = 1,
	CrawlSpeed = 3, -- studs/s while downed; jumping is disabled
}

-- Revive by another living explorer: server-timed, interruptible, nearby.
Config.Revive = {
	Duration = 4,
	MaxDistance = 9, -- server check, re-validated every tick
	PromptDistance = 7, -- client prompt visibility
	HealthRestored = 35,
}

-- Self-rescue with a carried kit (Decided: a limited self-rescue item; limit Open).
Config.SelfRescue = {
	Duration = 5,
	HealthRestored = 25,
	PerExpedition = 1, -- successful self-rescues allowed per run
}

-- Ordinary items: session-only, never registered or protected, dropped on final death.
-- maxCarry is the capacity; townRefill is what the free town station tops up to.
Config.Items = {
	StarterBlade = {
		displayName = "Starter blade",
		kind = "Weapon",
		maxCarry = 1,
		townRefill = 1,
		damage = 18,
		range = 7, -- studs from the attacker's center to the target's edge
		arcDegrees = 110, -- total width of the swing in front of the attacker
		windup = 0.25, -- seconds before the hit is resolved
		cooldown = 0.8, -- seconds between swings (includes the windup)
	},
	Bandage = {
		displayName = "Bandage",
		kind = "Bandage",
		maxCarry = 5,
		townRefill = 3,
		heal = 35,
		useTime = 2.5, -- interruptible: taking damage cancels it, nothing is consumed
	},
	RescueKit = {
		displayName = "Self-rescue kit",
		kind = "RescueKit",
		maxCarry = 2,
		townRefill = 1,
	},
}
Config.ItemOrder = { "StarterBlade", "Bandage", "RescueKit" }

Config.Combat = {
	PlayerVsPlayer = false, -- PvE milestone: players cannot damage players (PvP design unchanged, later)
	RangeTolerance = 1.5, -- server slack for latency, studs
	HitFlashSeconds = 0.15,
}

-- Zones where the new combat and creature damage cannot happen. Creatures do not
-- enter or chase into them, and players cannot attack from inside them.
Config.ProtectedZones = { Town = true, Camp = true }

--[[
	Creatures. One original placeholder archetype; variants change numbers only.
	Names are provisional. Every variant uses the same AI (CreatureBrain).
	Guardians telegraph longer and recover longer after striking: that recovery is the
	attack opening, so a prepared solo player can win without inflated health alone.
]]
Config.Creatures = {
	MaxActive = 12,
	TickInterval = 0.2, -- seconds between AI updates
	DormantRadius = 180, -- creatures with no player this close skip perception
	RepathInterval = 1.0, -- minimum seconds between path computations per creature
	MaxPathFailures = 3, -- failed or stuck paths before giving up a target
	DirectChaseDistance = 30, -- chase straight when line of sight is clear and this close
	StuckSeconds = 2, -- no progress for this long counts as a path failure
	FadeSeconds = 2, -- corpse fade before removal
	Variants = {
		Regular = {
			displayName = "Thornback",
			scale = 1,
			color = Color3.fromRGB(95, 110, 80),
			health = 60,
			damage = 15,
			walkSpeed = 8,
			pursuitSpeed = 15,
			detectRadius = 45,
			hearRadius = 10, -- noticed without line of sight inside this distance
			fovDegrees = 120,
			loseSightSeconds = 3,
			attackRange = 6,
			attackArcDegrees = 90,
			windup = 0.8, -- telegraph before the strike
			recovery = 1.0, -- vulnerable pause after striking
			patrolRadius = 14,
			leashRadius = 55, -- from the den; beyond this the creature returns and resets
			respawnSeconds = 90,
		},
		Guardian = {
			displayName = "Thornback Matriarch",
			scale = 1.6,
			color = Color3.fromRGB(120, 70, 60),
			health = 180,
			damage = 25,
			walkSpeed = 6,
			pursuitSpeed = 12,
			detectRadius = 38,
			hearRadius = 12,
			fovDegrees = 140,
			loseSightSeconds = 4,
			attackRange = 8,
			attackArcDegrees = 100,
			windup = 1.2,
			recovery = 2.4, -- the guardian's clear attack opening
			patrolRadius = 6,
			leashRadius = 40,
			respawnSeconds = 180, -- encounter reset after its reward was claimed
		},
	},
}

-- Guardian encounters: one reward per cycle, generated by SpecimenFactory when the
-- guardian falls. Weights and quality bands are provisional (Open).
Config.Encounters = {
	RewardTable = {
		{ typeId = "Windhook", weight = 1, qualityMin = 0.55, qualityMax = 0.97 },
		{ typeId = "EchoLens", weight = 1, qualityMin = 0.55, qualityMax = 0.97 },
	},
	CachePromptDistance = 8,
	-- An environmental loss (fell out of the world) gives no reward; the encounter
	-- resets after this many seconds.
	LostGuardianResetSeconds = 30,
}

-- Ordinary item drops (world loot).
Config.Loot = {
	PromptMaxDistance = 8,
	ServerMaxDistance = 12,
	HoldDuration = 0.3,
	DropLifetime = 600, -- seconds before an untouched ordinary-item drop is removed
}

-- Free town supply station (testing). Tops items up to their townRefill amounts.
Config.Supply = {
	PromptMaxDistance = 10,
	ServerMaxDistance = 14,
	HoldDuration = 0.5,
}

Config.Zones = {
	CheckInterval = 0.25, -- seconds between server position checks
}

-- CollectionService tags. Hand-built geometry can use these tags instead of the dev map.
-- Marker attributes are documented in README.md ("Placing encounters and camps").
Config.Tags = {
	RelicSpawn = "HB_RelicSpawn",
	WorldRelic = "HB_WorldRelic",
	RegistrationTerminal = "HB_RegistrationTerminal",
	ServiceStation = "HB_ServiceStation", -- must stand inside a town zone
	SupplyStation = "HB_SupplyStation", -- must stand inside a town zone
	TownZone = "HB_TownZone",
	CampZone = "HB_CampZone",
	CreatureSpawn = "HB_CreatureSpawn", -- attributes: Variant, EncounterId (guardians)
	RelicCache = "HB_RelicCache", -- attribute: EncounterId
	Creature = "HB_Creature", -- set by the server on spawned creatures
	WorldLoot = "HB_WorldLoot", -- set by the server on ordinary-item drops
}

-- Development-only switches. All of these only take effect inside Roblox Studio.
Config.Dev = {
	BuildPlaceholderMap = true, -- build town, camp, and expedition placeholders at runtime
	BuildServiceStation = true, -- add a service station next to the registration terminal if none is tagged
	BuildRelicFixtures = true, -- add pedestals C-E for the milestone 3 test specimens
	BuildSupplyStation = true, -- add a supply station next to the registration terminal if none is tagged
	BuildEncounterFixtures = true, -- add a test arena with creatures, a guardian cache, and a camp
	RunSelfTest = true, -- run the logic tests (mock storage only) on server start
	EnableDevRemotes = true, -- create dev remotes for range, race, and repeated-death tests
	LogTraitsToServerOutput = true, -- print hidden traits in server Output (never sent to clients)
	TimedPickupInterval = 5, -- seconds; dev key J fires on the next multiple of this server time
}

return Config
