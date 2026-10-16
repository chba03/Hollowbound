--[[
	Provisional configuration (milestones 1-5).

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
			look = "Wildlife", -- milestone 5 dressing; cosmetic only
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
			displayName = "Rootwarden",
			look = "Construct", -- milestone 5: an ancient overgrown construct; cosmetic only
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

--[[
	Milestone 5: the vertical world. Geometry lives in src/server/World/Layout.luau
	(authored, deterministic); these are the shared, tunable numbers. Every value is a
	prototype choice (Open) unless a line says otherwise.

	Mode: "Vertical" uses the installed Workspace.HollowboundWorld (see README, "World
	installation"). "Legacy" uses the milestone 1-4 runtime dev map and fixtures.
	Services only bind to markers of the active mode, so nothing appears twice.
]]
Config.World = {
	Mode = "Vertical",
	-- In Studio, if the vertical world is not installed yet, fall back to the legacy dev map
	-- (loudly) so playtests still work. Live servers never build the legacy map.
	LegacyFallbackInStudio = true,
	ModelName = "HollowboundWorld",
	AuthoredFolderName = "AuthoredDecor", -- never touched by the installer
	LayoutVersion = "m5-1",

	-- Rim center at the walkable rim surface. Far from the old dev map (X=200) and the
	-- Baseplate template (|X|, |Z| <= 1024, Y <= 0).
	Origin = { X = 0, Y = 600, Z = 4000 },

	OpeningRadius = 210, -- the shaft opening at the rim (about 420 studs across)
	TownOuterRadius = 345, -- the paved rim ring ends here; hills continue to BoundaryRadius
	BoundaryRadius = 560, -- outer ridge that keeps players in the world
	FloorDepth = 380, -- first depth's floor, studs below the rim surface
	LowerDarkDepth = 520, -- background "further descent" scenery ends here (not playable)
	KillDepth = 560, -- below the rim; anything lower is lost to the dark (void defeat)

	MetersPerStud = 0.3, -- depth readout only (a character is about 5.5 studs tall)
	-- Region names by depth when no named place applies (studs below the rim).
	DepthBands = {
		{ from = -math.huge, name = "Rim Town" },
		{ from = 2, name = "Upper Shaft" },
		{ from = 110, name = "Hanging Gardens" },
		{ from = 300, name = "Verdant Floor" },
		{ from = 400, name = "The Lower Dark" },
	},

	-- Starting palette (prototype, from the milestone 5 brief: forest greens, pale stone,
	-- cool shaded water, warm sunlight, restrained relic accents; town wood, weathered
	-- stone, workshops). RGB 0-255. Swap freely; the installer reads it on each install.
	Palette = {
		PaleStone = { 214, 206, 188 },
		WeatheredStone = { 168, 160, 146 },
		MossStone = { 122, 138, 104 },
		DarkStone = { 70, 72, 74 },
		AbyssStone = { 34, 38, 44 },
		Cobble = { 150, 142, 128 },
		RootWood = { 96, 72, 52 },
		Timber = { 138, 100, 66 },
		WeatheredWood = { 156, 132, 104 },
		RoofClay = { 128, 70, 52 },
		RoofSlate = { 84, 92, 104 },
		Leaf = { 78, 132, 72 },
		LeafLight = { 120, 168, 86 },
		DeepLeaf = { 46, 92, 60 },
		Moss = { 96, 128, 70 },
		Vine = { 70, 120, 64 },
		Grass = { 104, 140, 78 },
		Water = { 120, 170, 196 },
		Mist = { 210, 228, 230 },
		RelicAccent = { 120, 220, 255 },
		WarmLight = { 255, 196, 128 },
		CrystalGlow = { 140, 230, 210 },
		Cloth = { 170, 140, 100 },
	},

	-- Lighting preset applied by the installer. The previous Lighting properties and any
	-- existing Atmosphere are saved in Lighting.HollowboundLightingBackup and restored
	-- by Installer.restoreLighting(). Other effects are left alone. Lighting.Technology
	-- is not set (set it in Studio; README recommends ShadowMap or Future).
	ApplyLightingPreset = true,
	LightingPreset = "VerdantRim",
	LightingPresets = {
		VerdantRim = {
			Lighting = {
				ClockTime = 14.2,
				GeographicLatitude = 28,
				Brightness = 2.4,
				Ambient = { 88, 92, 96 },
				OutdoorAmbient = { 128, 128, 120 },
				ColorShift_Top = { 255, 236, 205 },
				ColorShift_Bottom = { 60, 80, 70 },
				EnvironmentDiffuseScale = 0.6,
				EnvironmentSpecularScale = 0.4,
				ExposureCompensation = 0.1,
				GlobalShadows = true,
			},
			Atmosphere = { Density = 0.33, Offset = 0.2, Color = { 199, 214, 210 }, Decay = { 110, 125, 108 }, Glare = 0.25, Haze = 1.4 },
			Bloom = { Intensity = 0.4, Size = 24, Threshold = 1.6 },
			ColorCorrection = { Brightness = 0.02, Contrast = 0.08, Saturation = 0.06, TintColor = { 255, 250, 240 } },
			SunRays = { Intensity = 0.06, Spread = 0.8 },
			-- Client-side, local only: denser and cooler air toward the floor.
			DepthBlend = { Density = 0.45, Color = { 170, 200, 196 }, TintColor = { 228, 242, 238 } },
		},
	},
}

-- Camera: adjustable third person (player-controlled zoom), sensible occlusion.
Config.Camera = {
	MinZoom = 0.5,
	MaxZoom = 140, -- generous, so overlooks and next landings are visible
	FieldOfView = 72,
}

-- Environmental fall damage (milestone 5, provisional): without it, jumping into the
-- abyss would be a free descent. It goes through Vitals, so a lethal fall downs you.
-- Falls are environmental: protected zones do not cancel them.
Config.Falls = {
	Enabled = true,
	SafeSpeed = 85, -- impact speed (studs/s) with no damage (about an 18-stud drop)
	LethalSpeed = 170, -- impact speed that deals MaxDamage (about a 74-stud drop)
	MaxDamage = 100,
}

-- Interaction reach for terminals, stations, pickups, and the town desk: distance,
-- height difference, and a clear line, so nothing works from below or through floors.
Config.Reach = {
	MaxHeightDifference = 6,
}

-- Explorer gear (cosmetic, welded, massless, non-colliding; hitboxes unchanged).
Config.Outfit = {
	Enabled = true,
	LanternDepth = 120, -- the hip lantern lights below this depth (studs)
	-- Optional body proportions toward the slender explorer look. Off by default: scaling
	-- changes hitboxes and reach, which this milestone must not change silently.
	SlenderProportions = false,
}

-- Server-timed poses (Motor6D offsets) for actions that have no animation clip yet.
Config.Poses = {
	Enabled = true,
	BlendSeconds = 0.15,
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
	TownSpawn = "HB_TownSpawn", -- milestone 5: the SpawnLocation players use in the active world
	Region = "HB_Region", -- milestone 5: named place (attributes RegionName, Radius, Height, Priority)
	CreatureSpawn = "HB_CreatureSpawn", -- attributes: Variant, EncounterId (guardians)
	RelicCache = "HB_RelicCache", -- attribute: EncounterId
	Creature = "HB_Creature", -- set by the server on spawned creatures
	WorldLoot = "HB_WorldLoot", -- set by the server on ordinary-item drops
}

-- Development-only switches. All of these only take effect inside Roblox Studio.
Config.Dev = {
	-- The legacy runtime builders below apply only in Config.World.Mode = "Legacy" (or the
	-- Studio fallback when the vertical world is not installed).
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
