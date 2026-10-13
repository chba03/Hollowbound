--[[
	Provisional configuration.

	Design status labels follow docs/Hollowbound_Game_Design_v0_2.pdf:
	  Decided   - explicit design choice
	  Delegated - assistant recommendation adopted as the working direction
	  Proposed  - illustrative example, not selected
	  Open      - still needs a decision or testing
	Every number in this file is a placeholder for testing, not a balance decision.

	Milestone 2 adds the rim town (8 plots), the Hollow (10 layers), rope progression,
	relic displays with passive income, and saved player data. Those come from the
	project owner's milestone 2 brief. The design record lists displays as an Open
	"home for the collection"; rope-gated depth and passive income are new to this brief.
]]

local Config = {}

-- Rarity tiers, from the project owner's relic brief: Common, Uncommon, Mythic,
-- Secret, Divine, Eternal, Godly. Every relic type belongs to exactly one tier, shown
-- on pickup. Eternal (project owner) sits between Divine and Godly, a little less rare
-- than Godly, and spawns from layer 4 down.
-- Open: tier names stay as briefed; weights, income, and colours are placeholders.
--   weight  = spawn chance relative to the other tiers in the same layer (percent).
--             Divine, Eternal, and Godly have weight 0: they never come from the
--             normal refills, only from rare spawns (Config.RareSpawns), so they stay
--             rare. Layers 1-2 have no Divine, Eternal, or Godly relics, layer 3 only
--             Divine, and layer 4 no Godly
--   income  = base cash per second on display, before the type and layer multipliers
--   quality = bonus added to the layer's specimen quality band (better hidden traits)
--   light / sparkle / pillar / scale = how the relic shows in the world
Config.Rarities = {
	{ id = "Common", weight = 60, income = 1, quality = 0, color = Color3.fromRGB(205, 205, 205), light = 6, sparkle = 0, pillar = false, scale = 1 },
	{ id = "Uncommon", weight = 26, income = 3, quality = 0.05, color = Color3.fromRGB(100, 210, 120), light = 8, sparkle = 0, pillar = false, scale = 1.05 },
	{ id = "Mythic", weight = 10, income = 12, quality = 0.1, color = Color3.fromRGB(170, 100, 255), light = 10, sparkle = 2, pillar = false, scale = 1.15 },
	{ id = "Secret", weight = 3, income = 50, quality = 0.15, color = Color3.fromRGB(255, 70, 110), light = 12, sparkle = 4, pillar = false, scale = 1.25 },
	{ id = "Divine", weight = 0, income = 250, quality = 0.2, color = Color3.fromRGB(255, 215, 90), light = 14, sparkle = 8, pillar = true, scale = 1.35 },
	{ id = "Eternal", weight = 0, income = 700, quality = 0.22, color = Color3.fromRGB(255, 130, 45), light = 16, sparkle = 11, pillar = true, scale = 1.42 },
	{ id = "Godly", weight = 0, income = 1500, quality = 0.25, color = Color3.fromRGB(120, 255, 235), light = 18, sparkle = 14, pillar = true, scale = 1.5 },
}
Config.RarityById = {}
for index, tier in Config.Rarities do
	tier.rank = index
	Config.RarityById[tier.id] = tier
end

-- How far each trait may stray from the specimen's overall quality (0..1 scale).
Config.TraitSpread = 0.1

-- Trait vocabulary. A specimen's traits are rolled from its quality and stay hidden
-- until appraisal (Delegated). Labels and ranges are placeholders (Open).
Config.Traits = {
	reach = { label = "Reach", unit = "studs", min = 20, max = 60, decimals = 0 },
	cargoSupport = { label = "Carrying strength", unit = "", min = 0.2, max = 1.0, decimals = 2 },
	efficiency = { label = "Charge efficiency", unit = "", min = 0.2, max = 1.0, decimals = 2 },
	scanRange = { label = "Scan range", unit = "studs", min = 15, max = 80, decimals = 0 },
	fuelUse = { label = "Crystal efficiency", unit = "", min = 0.2, max = 1.0, decimals = 2 },
	silence = { label = "Silence", unit = "", min = 0.2, max = 1.0, decimals = 2 },
	duration = { label = "Duration", unit = "s", min = 4, max = 20, decimals = 0 },
	strainReduction = { label = "Strain reduction", unit = "", min = 0.05, max = 0.5, decimals = 2 },
	recharge = { label = "Recharge", unit = "", min = 0.2, max = 1.0, decimals = 2 },
	sight = { label = "Sight distance", unit = "studs", min = 30, max = 150, decimals = 0 },
	clarity = { label = "Clarity", unit = "", min = 0.2, max = 1.0, decimals = 2 },
	attunement = { label = "Attunement", unit = "", min = 0.2, max = 1.0, decimals = 2 },
	noise = { label = "Quietness", unit = "", min = 0.1, max = 1.0, decimals = 2 },
	warmth = { label = "Warmth", unit = "", min = 0.1, max = 1.0, decimals = 2 },
	buoyancy = { label = "Buoyancy", unit = "", min = 0.1, max = 1.0, decimals = 2 },
	resonance = { label = "Resonance", unit = "Hz", min = 40, max = 400, decimals = 0 },
	growth = { label = "Growth", unit = "", min = 0.1, max = 1.0, decimals = 2 },
	ward = { label = "Ward strength", unit = "", min = 0.1, max = 1.0, decimals = 2 },
	pull = { label = "Pull", unit = "studs", min = 5, max = 40, decimals = 0 },
	glow = { label = "Glow", unit = "studs", min = 4, max = 40, decimals = 0 },
	stability = { label = "Stability", unit = "", min = 0.1, max = 1.0, decimals = 2 },
	memory = { label = "Memory", unit = "s", min = 10, max = 120, decimals = 0 },
	pulse = { label = "Pulse rate", unit = "/min", min = 6, max = 90, decimals = 0 },
	cold = { label = "Chill", unit = "", min = 0.1, max = 1.0, decimals = 2 },
	vitality = { label = "Vitality", unit = "", min = 0.1, max = 1.0, decimals = 2 },
}

--[[
	The relic catalogue: 70 types. Layers 1-2 hold Common to Secret, layer 3 adds
	Divine, layer 4 adds Eternal, and layers 5-10 hold every tier (two Divine, one
	Eternal, and two Godly types each), so each step down and each tier up is worth more.
	The six types from the design record's illustrative catalogue (Proposed) keep their
	IDs and trait IDs so saved specimens still load.

	Columns: id, displayName, layer (where it spawns), rarity (tier id), value (type
	multiplier on display income), shape, color, accent, material (the world model, see
	server RelicModels), traits (ids from Config.Traits), requiresActivation, blurb.
	Shapes follow the relic reference sheet supplied by the project owner; every name is
	original. All values are placeholders (Open).
]]
local M = Enum.Material
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local CATALOGUE = {
	-- Layer 1: Mistfall Gardens
	{ "Windhook", "Windhook", 1, "Common", 1.0, "hook", rgb(120, 100, 80), rgb(200, 60, 50), M.Wood, { "reach", "cargoSupport", "efficiency" }, true, "A curled horn that tugs toward the open air." },
	{ "DewbeadString", "Dewbead String", 1, "Uncommon", 1.1, "beads", rgb(140, 210, 220), rgb(220, 250, 255), M.Glass, { "buoyancy", "clarity" }, false, "Beads of hardened mist, cool to the touch." },
	{ "VerdantKnot", "Verdant Knot", 1, "Mythic", 1.15, "knot", rgb(120, 130, 80), rgb(210, 180, 90), M.Slate, { "growth", "ward" }, false, "A woven plaque whose moss never dries." },
	{ "Sproutstone", "Sproutstone", 1, "Secret", 1.2, "layered", rgb(150, 190, 120), rgb(230, 225, 200), M.Limestone, { "growth", "vitality" }, false, "Banded stone with a seed asleep inside." },

	-- Layer 2: The Hanging Wood
	{ "EchoLens", "Echo Lens", 2, "Common", 1.0, "disc", rgb(130, 125, 115), rgb(200, 190, 170), M.Slate, { "scanRange", "fuelUse" }, false, "A stone lens that hums back what it hears." },
	{ "Rootcross", "Rootcross", 2, "Uncommon", 1.1, "cross", rgb(130, 95, 65), rgb(200, 185, 150), M.Wood, { "stability", "ward" }, false, "Two roots grown around each other by choice." },
	{ "HangingCoil", "Hanging Coil", 2, "Mythic", 1.15, "coil", rgb(150, 150, 145), rgb(90, 90, 90), M.Metal, { "pull", "stability" }, false, "A spring that only ever winds upward." },
	{ "InvertedSeed", "Inverted Seed", 2, "Secret", 1.2, "podball", rgb(150, 115, 85), rgb(225, 215, 190), M.Pebble, { "growth", "buoyancy" }, false, "Planted, it grows toward the ground." },

	-- Layer 3: Veilfall Cliffs
	{ "Stillbell", "Stillbell", 3, "Common", 1.0, "bell", rgb(150, 160, 165), rgb(220, 220, 210), M.Metal, { "silence", "duration" }, false, "Struck, it swallows every nearby sound." },
	{ "SprayPrism", "Spray Prism", 3, "Uncommon", 1.1, "prism", rgb(170, 215, 240), rgb(255, 255, 255), M.Glass, { "clarity", "buoyancy" }, false, "Rainbows hang around it even in shade." },
	{ "CascadeBeads", "Cascade Beads", 3, "Mythic", 1.15, "beads", rgb(80, 190, 210), rgb(200, 245, 255), M.Glass, { "pull", "buoyancy" }, false, "They roll uphill, like water reversed." },
	{ "VeilMirror", "Veil Mirror", 3, "Secret", 1.2, "disc", rgb(195, 205, 210), rgb(90, 120, 140), M.Foil, { "sight", "clarity" }, false, "Shows the cliff as it was, not as it is." },
	{ "ThunderSpiral", "Thunder Spiral", 3, "Divine", 1.25, "spiral", rgb(220, 230, 240), rgb(120, 170, 255), M.Marble, { "resonance", "pulse", "efficiency" }, true, "It roars faintly, like the great falls." },

	-- Layer 4: Glasswood Hollows
	{ "AnchorCharm", "Anchor Charm", 4, "Common", 1.0, "knot", rgb(110, 115, 120), rgb(170, 175, 180), M.Metal, { "strainReduction", "recharge" }, true, "Heavy for its size; it steadies the climb." },
	{ "FrostShard", "Frost Shard", 4, "Uncommon", 1.1, "prism", rgb(150, 220, 245), rgb(230, 250, 255), M.Ice, { "cold", "clarity" }, false, "Never melts, even held in a warm hand." },
	{ "CupwoodSeed", "Cupwood Seed", 4, "Mythic", 1.15, "podball", rgb(80, 170, 165), rgb(200, 240, 230), M.Glass, { "growth", "cold" }, false, "Seed of the cup trees, glassy and slow." },
	{ "GlassLattice", "Glass Lattice", 4, "Secret", 1.2, "coil", rgb(190, 235, 250), rgb(120, 190, 220), M.Glass, { "resonance", "stability" }, false, "A cage of crystal threads that rings softly." },
	{ "RimecallerFang", "Rimecaller Fang", 4, "Divine", 1.25, "bonehook", rgb(225, 240, 250), rgb(120, 180, 230), M.Marble, { "cold", "ward", "reach" }, true, "Frost spreads from wherever it points." },
	{ "AuroraCrown", "Aurora Crown", 4, "Eternal", 1.3, "ringsphere", rgb(150, 230, 255), rgb(255, 150, 230), M.Glass, { "cold", "glow", "attunement" }, true, "The northern lights, frozen mid-dance." },

	-- Layer 5: Drowned Terraces
	{ "SiltTablet", "Silt Tablet", 5, "Common", 1.0, "layered", rgb(150, 140, 120), rgb(90, 85, 80), M.Slate, { "memory", "stability" }, false, "Layers of river silt pressed into stone." },
	{ "Tidecross", "Tidecross", 5, "Uncommon", 1.1, "cross", rgb(90, 75, 60), rgb(160, 200, 200), M.Wood, { "buoyancy", "ward" }, false, "Driftwood that always floats upright." },
	{ "PathfindersEye", "Pathfinder's Eye", 5, "Mythic", 1.15, "disc", rgb(120, 125, 120), rgb(70, 170, 160), M.Slate, { "sight", "clarity" }, true, "Its eye turns toward the way out." },
	{ "DrownedBell", "Drowned Bell", 5, "Secret", 1.2, "bell", rgb(70, 130, 120), rgb(200, 180, 120), M.CorrodedMetal, { "resonance", "silence" }, false, "It rings only when held under water." },
	{ "DeepwaterPearls", "Deepwater Pearls", 5, "Divine", 1.25, "beads", rgb(60, 80, 110), rgb(200, 220, 255), M.Glass, { "buoyancy", "glow", "memory" }, false, "Dark pearls with a light deep inside." },
	{ "Floodcrown", "Floodcrown", 5, "Godly", 1.3, "folded", rgb(70, 140, 150), rgb(200, 255, 245), M.Glass, { "pull", "buoyancy", "vitality" }, true, "Folded water, held in a shape it remembers." },
	{ "SunkenLantern", "Sunken Lantern", 5, "Divine", 1.35, "bell", rgb(50, 110, 105), rgb(255, 210, 120), M.CorrodedMetal, { "glow", "silence", "memory" }, false, "Still lit after centuries under the water." },
	{ "Tideheart", "Tideheart", 5, "Godly", 1.4, "ringsphere", rgb(30, 70, 120), rgb(140, 230, 255), M.Glass, { "pull", "buoyancy", "pulse" }, true, "Every terrace fills and drains to its beat." },
	{ "MaelstromCore", "Maelstrom Core", 5, "Eternal", 1.3, "spiral", rgb(40, 90, 130), rgb(120, 255, 230), M.Glass, { "pull", "buoyancy", "pulse" }, true, "A whirlpool that never stopped turning." },

	-- Layer 6: Rootbound Ruins
	{ "RustedSeal", "Rusted Seal", 6, "Common", 1.0, "disc", rgb(130, 100, 80), rgb(80, 70, 60), M.CorrodedMetal, { "ward", "memory" }, false, "A stamped seal from a builder no one knows." },
	{ "RuinBrick", "Ruin Brick", 6, "Uncommon", 1.1, "layered", rgb(170, 160, 140), rgb(110, 80, 60), M.Brick, { "stability", "memory" }, false, "A brick that still remembers its wall." },
	{ "WayfarerKey", "Wayfarer Key", 6, "Mythic", 1.15, "cross", rgb(180, 160, 120), rgb(110, 80, 55), M.Wood, { "attunement", "noise" }, true, "It fits locks that are not there yet." },
	{ "RootEffigy", "Root Effigy", 6, "Secret", 1.2, "bonehook", rgb(120, 90, 60), rgb(200, 170, 120), M.Wood, { "growth", "ward" }, false, "Roots grown into the shape of a figure." },
	{ "ClockworkLattice", "Clockwork Lattice", 6, "Divine", 1.25, "coil", rgb(180, 150, 90), rgb(110, 90, 60), M.Metal, { "pulse", "stability", "memory" }, true, "Gears inside still tick, slowly, toward something." },
	{ "FoundersSeal", "Founder's Seal", 6, "Godly", 1.3, "knot", rgb(200, 170, 90), rgb(255, 235, 160), M.Foil, { "ward", "attunement", "memory" }, true, "The mark of whoever built the ruins first." },
	{ "WardensPrism", "Warden's Prism", 6, "Divine", 1.35, "prism", rgb(230, 170, 70), rgb(255, 240, 190), M.Glass, { "ward", "clarity", "glow" }, true, "It once lit the ruins' great gate." },
	{ "GearOfAges", "Gear of Ages", 6, "Godly", 1.4, "disc", rgb(205, 165, 70), rgb(120, 90, 50), M.Foil, { "pulse", "memory", "stability" }, true, "Turn it once and the ruins remember being whole." },
	{ "EverwoundClock", "Everwound Clock", 6, "Eternal", 1.3, "disc", rgb(190, 150, 80), rgb(255, 120, 60), M.Foil, { "pulse", "memory", "stability" }, true, "Its hands move backward, and never slow." },

	-- Layer 7: The Marrow
	{ "MarrowNodule", "Marrow Nodule", 7, "Common", 1.0, "lumpball", rgb(170, 160, 140), rgb(220, 210, 190), M.Pebble, { "vitality", "pulse" }, false, "Warm, and very faintly beating." },
	{ "SporePod", "Spore Pod", 7, "Uncommon", 1.1, "spikeball", rgb(115, 95, 70), rgb(220, 210, 180), M.Pebble, { "growth", "pulse" }, false, "Shakes when something alive comes near." },
	{ "BoundSpiral", "Bound Spiral", 7, "Mythic", 1.15, "spiral", rgb(230, 225, 205), rgb(200, 255, 120), M.Marble, { "pulse", "vitality" }, false, "Bone bands bound around a green glow." },
	{ "LivingCube", "Living Cube", 7, "Secret", 1.2, "folded", rgb(110, 120, 70), rgb(200, 240, 160), M.Fabric, { "growth", "memory" }, false, "Folds and unfolds itself while you sleep." },
	{ "MarrowFang", "Marrow Fang", 7, "Divine", 1.25, "bonehook", rgb(235, 230, 215), rgb(90, 80, 70), M.Marble, { "reach", "vitality", "pull" }, true, "Grown, not carved, from something enormous." },
	{ "UnbornStar", "The Unborn Star", 7, "Godly", 1.3, "ringsphere", rgb(250, 230, 160), rgb(255, 255, 220), M.Neon, { "glow", "vitality", "attunement" }, true, "A light from near the bottom of the Hollow." },
	{ "SporeSovereign", "Spore Sovereign", 7, "Divine", 1.35, "spikeball", rgb(90, 120, 60), rgb(210, 255, 120), M.Pebble, { "growth", "vitality", "pulse" }, false, "Every spore in the Marrow leans toward it." },
	{ "Marrowheart", "Marrowheart", 7, "Godly", 1.4, "lumpball", rgb(170, 60, 60), rgb(255, 170, 120), M.Glass, { "vitality", "pulse", "warmth" }, true, "It beats. The whole Hollow beats with it." },
	{ "FirstHeartbeat", "First Heartbeat", 7, "Eternal", 1.3, "lumpball", rgb(200, 80, 70), rgb(255, 140, 60), M.Glass, { "vitality", "pulse", "warmth" }, true, "The Hollow's oldest pulse, kept in a shell." },

	-- Layer 8: Emberdeep Forges
	{ "SlagBead", "Slag Bead", 8, "Common", 1.0, "lumpball", rgb(70, 60, 55), rgb(255, 120, 40), M.Basalt, { "warmth", "stability" }, false, "Cooled slag with a coal still glowing inside." },
	{ "BellowsValve", "Bellows Valve", 8, "Uncommon", 1.1, "cross", rgb(120, 90, 60), rgb(255, 150, 60), M.CorrodedMetal, { "pull", "warmth" }, false, "It breathes in when no one is watching." },
	{ "CinderCoil", "Cinder Coil", 8, "Mythic", 1.15, "coil", rgb(90, 60, 45), rgb(255, 110, 30), M.Metal, { "warmth", "pulse" }, false, "A spring forged red-hot and never cooled." },
	{ "MagmaTablet", "Magma Tablet", 8, "Secret", 1.2, "layered", rgb(60, 45, 40), rgb(255, 90, 30), M.CrackedLava, { "memory", "warmth" }, false, "Writing in it flows like lava, then sets." },
	{ "AnvilSeal", "Anvil Seal", 8, "Divine", 1.25, "knot", rgb(80, 80, 85), rgb(255, 170, 80), M.Metal, { "stability", "ward", "warmth" }, true, "Struck once, it rings for a whole day." },
	{ "EmberChoir", "Ember Choir", 8, "Divine", 1.35, "bell", rgb(140, 70, 40), rgb(255, 200, 90), M.CorrodedMetal, { "resonance", "warmth", "glow" }, false, "A bell that sings in sparks." },
	{ "UndyingFlame", "Undying Flame", 8, "Eternal", 1.3, "prism", rgb(255, 120, 40), rgb(255, 230, 150), M.Neon, { "warmth", "glow", "vitality" }, true, "Lit before the Hollow had a name." },
	{ "Sunforge", "The Sunforge", 8, "Godly", 1.3, "ringsphere", rgb(255, 150, 50), rgb(255, 240, 180), M.Neon, { "warmth", "glow", "efficiency" }, true, "A small sun, hammered into a ring." },
	{ "MoltenCrown", "Molten Crown", 8, "Godly", 1.4, "folded", rgb(200, 80, 30), rgb(255, 200, 90), M.CrackedLava, { "warmth", "ward", "attunement" }, true, "Still dripping, and never any smaller." },

	-- Layer 9: Gloamcap Grotto
	{ "Glowcap", "Glowcap", 9, "Common", 1.0, "podball", rgb(110, 80, 140), rgb(190, 140, 255), M.Pebble, { "glow", "growth" }, false, "A mushroom cap that glows when squeezed." },
	{ "SporeLantern", "Spore Lantern", 9, "Uncommon", 1.1, "bell", rgb(80, 60, 110), rgb(150, 255, 220), M.Glass, { "glow", "silence" }, false, "Spores drift inside like slow fireflies." },
	{ "GloamThread", "Gloam Thread", 9, "Mythic", 1.15, "spiral", rgb(60, 50, 90), rgb(200, 120, 255), M.Fabric, { "pull", "attunement" }, false, "Fungal silk that pulls toward the dark." },
	{ "MyceliumEye", "Mycelium Eye", 9, "Secret", 1.2, "disc", rgb(90, 70, 120), rgb(120, 255, 200), M.Slate, { "sight", "memory" }, true, "It sees through every root in the grotto." },
	{ "DreamSpore", "Dream Spore", 9, "Divine", 1.25, "spikeball", rgb(130, 80, 170), rgb(230, 180, 255), M.Pebble, { "growth", "memory", "clarity" }, false, "Breathe near it and you dream of the deep." },
	{ "VioletChime", "Violet Chime", 9, "Divine", 1.35, "beads", rgb(120, 70, 180), rgb(220, 190, 255), M.Glass, { "resonance", "glow", "silence" }, false, "Each bead hums a different note." },
	{ "Nightbloom", "Nightbloom", 9, "Eternal", 1.3, "folded", rgb(70, 40, 110), rgb(255, 140, 240), M.Glass, { "growth", "glow", "vitality" }, true, "A flower that has never closed." },
	{ "GloamSovereign", "Gloam Sovereign", 9, "Godly", 1.3, "lumpball", rgb(90, 50, 140), rgb(180, 255, 230), M.Neon, { "growth", "attunement", "pulse" }, true, "Every glowing thing in the grotto answers it." },
	{ "HollowMoon", "Hollow Moon", 9, "Godly", 1.4, "ringsphere", rgb(200, 190, 240), rgb(160, 120, 255), M.Glass, { "glow", "pull", "clarity" }, true, "A moon that only rises underground." },

	-- Layer 10: The Lumen Core
	{ "LumenShard", "Lumen Shard", 10, "Common", 1.0, "prism", rgb(230, 225, 210), rgb(255, 240, 180), M.Glass, { "glow", "clarity" }, false, "A splinter of the light at the bottom." },
	{ "HaloDisc", "Halo Disc", 10, "Uncommon", 1.1, "disc", rgb(240, 235, 220), rgb(255, 220, 140), M.Marble, { "ward", "glow" }, false, "A ring of light with nothing holding it up." },
	{ "Lightspring", "Lightspring", 10, "Mythic", 1.15, "coil", rgb(245, 240, 225), rgb(255, 230, 160), M.Foil, { "pulse", "efficiency" }, false, "A coil of solid light, warm to the touch." },
	{ "OriginStone", "Origin Stone", 10, "Secret", 1.2, "layered", rgb(220, 215, 200), rgb(255, 250, 220), M.Marble, { "memory", "stability" }, false, "Rock from before the Hollow was dug." },
	{ "DawnFeather", "Dawn Feather", 10, "Divine", 1.25, "bonehook", rgb(255, 245, 220), rgb(255, 210, 120), M.Marble, { "buoyancy", "glow", "vitality" }, true, "It falls upward, slowly, if you let go." },
	{ "RadiantCross", "Radiant Cross", 10, "Divine", 1.35, "cross", rgb(240, 230, 200), rgb(255, 240, 170), M.Foil, { "ward", "glow", "attunement" }, true, "It casts no shadow, only light." },
	{ "EverlightBeads", "Everlight Beads", 10, "Eternal", 1.3, "beads", rgb(255, 250, 235), rgb(255, 180, 90), M.Neon, { "glow", "memory", "vitality" }, true, "Each bead holds a dawn that never ended." },
	{ "HeartOfTheHollow", "Heart of the Hollow", 10, "Godly", 1.3, "lumpball", rgb(255, 245, 210), rgb(255, 255, 255), M.Neon, { "vitality", "pulse", "attunement" }, true, "The Hollow was dug to keep this hidden." },
	{ "FirstLight", "The First Light", 10, "Godly", 1.4, "ringsphere", rgb(255, 255, 240), rgb(255, 220, 140), M.Neon, { "glow", "clarity", "pull" }, true, "Everything bright in the world began here." },
}

Config.RelicTypes = {}
Config.RelicOrder = {} -- type ids in catalogue order (layer, then tier)
Config.RelicsByLayer = {} -- [layer][tier id] = { type ids }
for _, row in CATALOGUE do
	local id = row[1]
	local traits = {}
	for _, traitId in row[10] do
		local def = Config.Traits[traitId]
		assert(def, `Unknown trait {traitId} on relic {id}`)
		table.insert(traits, {
			id = traitId,
			label = def.label,
			unit = def.unit,
			min = def.min,
			max = def.max,
			decimals = def.decimals,
		})
	end
	local def = {
		displayName = row[2],
		layer = row[3],
		rarity = row[4],
		valueMultiplier = row[5],
		shape = row[6],
		color = row[7],
		accent = row[8],
		material = row[9],
		traits = traits,
		requiresActivation = row[11],
		blurb = row[12],
	}
	assert(Config.RarityById[def.rarity], `Unknown rarity {def.rarity} on relic {id}`)
	Config.RelicTypes[id] = def
	table.insert(Config.RelicOrder, id)
	local byTier = Config.RelicsByLayer[def.layer] or {}
	Config.RelicsByLayer[def.layer] = byTier
	byTier[def.rarity] = byTier[def.rarity] or {}
	table.insert(byTier[def.rarity], id)
end

-- Specimen size, from the project owner's brief: two finds of the same relic can differ
-- in size, and bigger ones earn more. Size is visible on pickup (not a hidden trait),
-- so income may use it. Each band is rolled by weight, then a size inside it.
-- Open: every number.
Config.Sizes = {
	Bands = {
		{ label = "Tiny", weight = 15, min = 0.6, max = 0.85 },
		{ label = "", weight = 58, min = 0.85, max = 1.25 },
		{ label = "Large", weight = 19, min = 1.3, max = 1.8 },
		{ label = "Huge", weight = 6.5, min = 2, max = 3 },
		{ label = "Colossal", weight = 1.5, min = 3.5, max = 5 },
	},
	IncomePower = 1.5, -- income multiplier = size ^ IncomePower (a 2x relic earns 2.8x)
	MaxWorldScale = 3.5, -- the model stops growing past this size in the Hollow
	MaxDisplayScale = 2, -- and past this on a pedestal, so neighbours stay visible
}

-- The Hollow: a vertical pit below the rim town. Geometry is located through the part
-- tagged Tags.HollowRim (its position is the pit centre at rim height); these sizes
-- tell the dev map how to build it and the server how to measure depth. The pit's
-- radius changes with depth (each layer's `radius`, blended between layer centres by
-- Progression.pitRadiusAt), so it bulges and narrows like a natural chasm.
Config.Hollow = {
	PitRadius = 120, -- pit radius at the rim; must equal Config.Layers[1].radius
	LedgeInnerRadius = 105, -- ledges run from here out to the wall
	RopeRadius = 100, -- ropes hang this far from the centre, just inside the ledges
	LayerHeight = 160, -- depth of each layer in studs
	LedgeDepths = { 56, 124 }, -- ledge tops, studs below each layer's top (multiples of 4 for terrain)
	TownDepthTolerance = 8, -- within this many studs of rim height and outside the pit = town
	SeaRecoverDepth = 30, -- below the rim and outside the pit by this much = fell into the sea
}

-- Open: layer names, atmosphere, and every number are placeholders. Names are original
-- (the design record wants original locations). The look follows the reference chart
-- supplied for milestone 2 and the record's Proposed "Atmosphere by region" table:
-- green gardens, an upside-down forest, a great waterfall cliff, a crystal forest of
-- cup-shaped trees, flooded terraces, root-bound ruins, and a living, glowing deep.
-- Layers 8-10 (project owner: three more, same style): molten forges, a grotto of
-- glowing mushrooms, and a pale, light-filled core at the very bottom.
--   incomeMultiplier = display income scale for relics from that layer. Fitted by a
--              progression simulation against the rope costs so a typical player
--              (about one relic a minute, best relics on display) spends about
--              8 min in layer 1, 25 min in layer 2, 1.5 h in layer 3, 4 h in layer 4,
--              and 12 h of play in each layer after that (about 67 h to layer 10).
--              Refitted for 10 layers with Divine, Eternal, and Godly out of the
--              normal refills (Config.RareSpawns).
--   quality  = specimen quality band rolled for relics found in that layer (a
--              relic's tier adds its own bonus; see Config.Rarities)
--   radius   = pit radius at the layer's centre (min 120 keeps ropes and ledges clear)
--   fog/tint/brightness/density = this layer's client atmosphere (LayerEffects)
--   motes    = this layer's ambient floating particles (LayerEffects)
Config.Layers = {
	{
		name = "Mistfall Gardens",
		quality = { 0.0, 0.45 },
		incomeMultiplier = 2,
		maxNodes = 6,
		radius = 120,
		fog = Color3.fromRGB(215, 232, 210),
		tint = Color3.fromRGB(248, 255, 242),
		brightness = 0.02,
		density = 0.22,
		motes = { color = Color3.fromRGB(255, 252, 220), rate = 6, size = 0.25, speed = 1, glow = 0.6 },
	},
	{
		name = "The Hanging Wood",
		quality = { 0.1, 0.6 },
		incomeMultiplier = 58,
		maxNodes = 6,
		radius = 126,
		fog = Color3.fromRGB(165, 185, 160),
		tint = Color3.fromRGB(235, 250, 235),
		brightness = -0.02,
		density = 0.35,
		motes = { color = Color3.fromRGB(200, 230, 180), rate = 8, size = 0.3, speed = 0.8, glow = 0.4 },
	},
	{
		name = "Veilfall Cliffs",
		quality = { 0.25, 0.72 },
		incomeMultiplier = 3100,
		maxNodes = 6,
		radius = 138,
		fog = Color3.fromRGB(228, 228, 218),
		tint = Color3.fromRGB(255, 252, 245),
		brightness = 0.04,
		density = 0.45,
		motes = { color = Color3.fromRGB(240, 245, 255), rate = 14, size = 0.3, speed = 2, glow = 0.3 },
	},
	{
		name = "Glasswood Hollows",
		quality = { 0.4, 0.82 },
		incomeMultiplier = 540e3,
		maxNodes = 5,
		radius = 172,
		fog = Color3.fromRGB(175, 215, 232),
		tint = Color3.fromRGB(220, 240, 255),
		brightness = 0,
		density = 0.38,
		motes = { color = Color3.fromRGB(200, 235, 255), rate = 10, size = 0.3, speed = 0.6, glow = 0.8 },
	},
	{
		name = "Drowned Terraces",
		quality = { 0.55, 0.9 },
		incomeMultiplier = 26e6,
		maxNodes = 5,
		radius = 150,
		fog = Color3.fromRGB(85, 135, 155),
		tint = Color3.fromRGB(200, 225, 240),
		brightness = -0.06,
		density = 0.48,
		motes = { color = Color3.fromRGB(150, 210, 230), rate = 6, size = 0.25, speed = 0.5, glow = 0.5 },
	},
	{
		name = "Rootbound Ruins",
		quality = { 0.65, 0.96 },
		incomeMultiplier = 340e6,
		maxNodes = 4,
		radius = 136,
		fog = Color3.fromRGB(120, 96, 72),
		tint = Color3.fromRGB(255, 230, 205),
		brightness = -0.1,
		density = 0.52,
		motes = { color = Color3.fromRGB(190, 160, 120), rate = 10, size = 0.2, speed = 0.4, glow = 0 },
	},
	{
		name = "The Marrow",
		quality = { 0.75, 1.0 },
		incomeMultiplier = 6.3e9,
		maxNodes = 4,
		radius = 124,
		fog = Color3.fromRGB(180, 150, 105),
		tint = Color3.fromRGB(255, 238, 205),
		brightness = -0.05,
		density = 0.5,
		motes = { color = Color3.fromRGB(230, 255, 140), rate = 12, size = 0.35, speed = 0.7, glow = 1 },
	},
	{
		name = "Emberdeep Forges",
		quality = { 0.8, 1.0 },
		incomeMultiplier = 110e9,
		maxNodes = 4,
		radius = 142,
		fog = Color3.fromRGB(125, 62, 36),
		tint = Color3.fromRGB(255, 220, 195),
		brightness = -0.05,
		density = 0.5,
		motes = { color = Color3.fromRGB(255, 140, 50), rate = 14, size = 0.2, speed = 1.6, glow = 1 },
	},
	{
		name = "Gloamcap Grotto",
		quality = { 0.84, 1.0 },
		incomeMultiplier = 2.4e12,
		maxNodes = 4,
		radius = 158,
		fog = Color3.fromRGB(62, 44, 92),
		tint = Color3.fromRGB(228, 210, 255),
		brightness = -0.07,
		density = 0.5,
		motes = { color = Color3.fromRGB(170, 140, 255), rate = 12, size = 0.3, speed = 0.4, glow = 1 },
	},
	{
		name = "The Lumen Core",
		quality = { 0.88, 1.0 },
		incomeMultiplier = 55e12,
		maxNodes = 3,
		radius = 132,
		fog = Color3.fromRGB(232, 222, 192),
		tint = Color3.fromRGB(255, 248, 230),
		brightness = 0.06,
		density = 0.42,
		motes = { color = Color3.fromRGB(255, 238, 185), rate = 14, size = 0.3, speed = 0.6, glow = 1 },
	},
}

-- Rare spawns (project owner): Divine, Eternal, and Godly relics never come from the
-- normal refills. Instead the server rolls for each tier every RollSeconds, with a chance
-- worked out so the tier appears with `perDay` probability over a day of play (Divine:
-- 60%, so about one every day or two). A spawn picks a random layer holding that tier,
-- is announced to everyone, and stays until night. A lit Lucky Lantern multiplies the
-- chances. Open: every number.
Config.RareSpawns = {
	RollSeconds = 60,
	Tiers = {
		{ tier = "Divine", perDay = 0.6 },
		{ tier = "Eternal", perDay = 0.22 },
		{ tier = "Godly", perDay = 0.18 },
	},
}

-- Night, from the project owner's brief: every CycleSeconds night falls. Every relic
-- lying in the Hollow fades, and every player outside town and outside a camp is pulled
-- back to their base, and again for anyone who goes back in during the night. At dawn
-- the Hollow refills with fresh relics. Unsecured relics stay with their carrier.
-- Open: every number.
Config.Night = {
	CycleSeconds = 300, -- nightfall every 5 minutes
	NightSeconds = 25, -- how long the night lasts before dawn
	Warnings = { 60, 30, 10 }, -- seconds before nightfall to warn everyone
	SweepInterval = 1, -- seconds between night checks for players in the Hollow
	ClockTime = 0.3, -- client sky time at night
}

-- Camps are round refuges. Radius and height of the safe area; a yellow ring on the
-- ground marks the edge. Open: sizes.
Config.Camps = {
	Radius = 9,
	Height = 14,
	RingColor = Color3.fromRGB(255, 214, 60),
	RingSegments = 28,
}

-- Climbing fatigue (server: Ascent; client: RopeController). Only while you carry an
-- unsecured relic of rank MinRank or higher (project owner: the two rarest tiers,
-- Eternal and Godly): once you have climbed LimitMeters up from the deepest point since
-- you picked it up or last rested, you cannot climb higher until you rest in a camp for
-- RestSeconds. Back in town it resets. Open: every number.
Config.Ascent = {
	MinRank = 6, -- Eternal and Godly
	LimitMeters = 100,
	RestSeconds = 5,
	CheckInterval = 0.25,
}

-- Carrying an unsecured relic of rank MarkRank or higher (5 = Divine) marks you red for
-- every player until you register it or lose it (server: RelicMarks).
Config.RelicMark = {
	MarkRank = 5,
	Color = Color3.fromRGB(255, 40, 40),
	CheckInterval = 1,
}

-- Server-wide announcements for rare spawns: tiers at or above this rank (5 = Divine).
Config.Announce = {
	MinRank = 5,
	Seconds = 7, -- how long each announcement stays on screen
}

-- Sprinting and stamina (server: Stamina; client: SprintController). For fleeing or
-- fighting creatures once they exist. Open: every number.
Config.Sprint = {
	WalkSpeed = 16, -- Roblox default
	SprintSpeed = 28,
	MaxStamina = 100,
	DrainPerSecond = 22, -- about 4.5 seconds of sprinting from full
	RegenPerSecond = 16, -- about 6 seconds to refill from empty
	RegenDelay = 1.2, -- seconds after sprinting before stamina regenerates
	MinToStart = 15, -- after running dry, stamina needed before you can sprint again
	MovingSpeed = 2, -- horizontal speed (studs/s) that counts as moving
	TickSeconds = 0.1,
}

-- The veil: a cloud layer each player sees in the Hollow more than LayersAhead layers
-- below the deepest layer their rope reaches (client DepthVeil). Faint sheets stacked
-- SheetGap apart, plus drifting clouds: things below are dim and hazy, not hidden.
-- Open: every number.
Config.Veil = {
	LayersAhead = 2, -- rope reaches layer 1: layers 2 and 3 clear, layer 4 and down veiled
	Sheets = 6,
	SheetGap = 14,
	SheetTransparency = 0.86, -- per sheet; six together let through about a third
	CloudRate = 7,
	CloudThickness = 30,
}

-- Falling (server FallDamage). Heights in studs; the HUD shows metres. A fall from one
-- ledge to the next (68 studs) is fatal, so rope length still decides how deep you can
-- safely go. Open: every number.
Config.Fall = {
	SafeStuds = 36, -- about 10 m: no damage up to here
	FatalStuds = 66, -- about 18.5 m: death and ragdoll from here
	MaxNonFatalDamage = 0.9, -- share of max health a just-survivable fall takes
	FallingSpeed = 14, -- studs/s downward that counts as falling
	LandedSpeed = 4, -- a fall ends when downward speed drops below this
	TeleportStuds = 60, -- a jump this big between frames is a teleport, not a fall
}

-- How distances are shown to players. Roblox's own guide: 1 stud is about 0.28 m.
Config.Display = {
	MetersPerStud = 0.28,
}

--[[
	The store: the Emporium menu (client ShopMenu) and its purchases (server Store).
	The project owner chose: paid progress (cash, upgrade levels), relic crates, game
	passes, and limited-time weekly offers.

	Ids: every productId / passId is 0 until it is created in the Creator Dashboard
	(Monetization > Developer Products / Passes) and pasted here. With id 0:
	  - in Studio, with StudioFreePurchases on, the item is granted free as a test
	  - in a live server, the item says it is not for sale yet
	`price` is the Robux price shown before the real price loads from Roblox.

	Item kinds and their fields:
	  cash        minutes, minimum   cash = your income x minutes (at least minimum)
	  level       upgrade            +1 level of RopeLength / RopeSpeed / BaseSlots
	  crate       layer, weights     a random registered relic from that layer
	  boost       boost, minutes     a timed personal boost (Config.Shop.Boosts)
	  serverLuck  minutes            rare relics more likely for everyone in the server
	  bundle      contents           a list of the above
	  pass        passId, perk       a permanent perk (Config.Shop.Perks)
	Open: every name, amount, price, and odds.
]]
Config.Shop = {
	Title = "Emporium",
	StudioFreePurchases = true,

	-- Permanent game pass perks.
	Perks = {
		DoubleIncome = { label = "Double Income", income = 2 },
		SwiftClimber = { label = "Swift Climber", climb = 1.5 },
		IronLungs = { label = "Iron Lungs", staminaDrain = 0.5, staminaRegen = 1.5 },
		Featherfall = { label = "Featherfall", fall = 1.3 }, -- survive one ledge drop, not a layer
	},

	-- Timed personal boosts. Buying more while active adds time.
	Boosts = {
		Income = { label = "2x income", income = 2 },
		Climb = { label = "2x climb speed", climb = 2 },
	},

	-- Lucky Lantern: every tier from Mythic up is this many times as likely, server-wide.
	ServerLuck = { multiplier = 2, minRank = 3 },

	-- Weekly offers: one at a time, rotating every week, each limited per player.
	Limited = {
		WeekSeconds = 7 * 24 * 3600,
		WeekOffset = 4 * 24 * 3600, -- weeks start Monday 00:00 UTC
		Stock = 3, -- purchases per player per week
		Offers = {
			{ id = "EmberCrate", name = "Ember Crate", detail = "A layer 7 relic, Divine to Godly odds x5", icon = "crate", price = 499, productId = 0,
				kind = "crate", layer = 7, weights = { Common = 30, Uncommon = 28, Mythic = 20, Secret = 14, Divine = 6, Eternal = 3, Godly = 2 } },
			{ id = "MidnightCache", name = "Midnight Cache", detail = "4 hours of income + a Lucky Lantern", icon = "chest", price = 399, productId = 0,
				kind = "bundle", contents = { { kind = "cash", minutes = 240, minimum = 500000 }, { kind = "serverLuck", minutes = 15 } } },
			{ id = "DelversKit", name = "Delver's Kit", detail = "+1 rope length, +1 climb speed, a layer 5 crate", icon = "rope", price = 349, productId = 3718286466,
				kind = "bundle", contents = { { kind = "level", upgrade = "RopeLength" }, { kind = "level", upgrade = "RopeSpeed" }, { kind = "crate", layer = 5 } } },
		},
	},

	-- Crate tier odds when an item gives none (only tiers the layer holds can come up).
	CrateWeights = { Common = 45, Uncommon = 30, Mythic = 15, Secret = 7, Divine = 2.4, Eternal = 0.8, Godly = 0.6 },

	Items = {
		DelversBundle = { name = "Delver's Bundle", detail = "1 hour of income, +1 rope length, a layer 3 crate", icon = "chest", price = 299, productId = 3718286509, tag = "BEST VALUE", wide = true,
			kind = "bundle", contents = { { kind = "cash", minutes = 60, minimum = 100000 }, { kind = "level", upgrade = "RopeLength" }, { kind = "crate", layer = 3 } } },

		Pocket = { name = "Pocket of Coins", icon = "coins", price = 49, productId = 3718286561, kind = "cash", minutes = 5, minimum = 5000 },
		Purse = { name = "Coin Purse", icon = "purse", price = 99, productId = 3718286599, kind = "cash", minutes = 15, minimum = 25000 },
		HeavyPurse = { name = "Heavy Purse", icon = "purse", price = 249, productId = 3718286639, kind = "cash", minutes = 60, minimum = 100000 },
		Chest = { name = "Treasure Chest", icon = "chest", price = 499, productId = 3718286667, kind = "cash", minutes = 240, minimum = 500000, wide = true },
		Vault = { name = "Guild Vault", icon = "chest", price = 799, productId = 3718286708, kind = "cash", minutes = 720, minimum = 2000000, wide = true, tag = "MOST CASH" },

		RopeLevel = { name = "Steel-Core Rope", icon = "rope", price = 149, productId = 3718286738, kind = "level", upgrade = "RopeLength" },
		SpeedLevel = { name = "Clockwork Winch", icon = "gear", price = 149, productId = 3718286767, kind = "level", upgrade = "RopeSpeed" },
		SlotLevel = { name = "Extra Pedestal", icon = "gear", price = 99, productId = 3718286797, kind = "level", upgrade = "BaseSlots" },

		MerchantLamp = { name = "Merchant's Lamp", detail = "2x income for 30 min", icon = "lantern", price = 99, productId = 0, kind = "boost", boost = "Income", minutes = 30 },
		ClimberLamp = { name = "Climber's Lamp", detail = "2x climb speed for 30 min", icon = "lantern", price = 79, productId = 0, kind = "boost", boost = "Climb", minutes = 30 },
		LuckyLantern = { name = "Lucky Lantern", detail = "2x rare relics for the whole server, 15 min", icon = "lantern", price = 149, productId = 0, kind = "serverLuck", minutes = 15, tag = "SERVER" },

		GardensCrate = { name = "Gardens Crate", detail = "A random layer 2 relic", icon = "crate", price = 49, productId = 0, kind = "crate", layer = 2 },
		CliffsCrate = { name = "Cliffs Crate", detail = "A random layer 4 relic", icon = "crate", price = 149, productId = 0, kind = "crate", layer = 4 },
		RuinsCrate = { name = "Ruins Crate", detail = "A random layer 6 relic", icon = "crate", price = 349, productId = 0, kind = "crate", layer = 6 },
		MarrowCrate = { name = "Marrow Crate", detail = "A random layer 7 relic", icon = "crate", price = 699, productId = 0, kind = "crate", layer = 7, tag = "RAREST" },

		DoubleIncomePass = { name = "Double Income", detail = "2x display income, forever", icon = "coins", price = 499, passId = 0, kind = "pass", perk = "DoubleIncome", wide = true },
		SwiftClimberPass = { name = "Swift Climber", detail = "1.5x climb speed, forever", icon = "rope", price = 249, passId = 0, kind = "pass", perk = "SwiftClimber" },
		IronLungsPass = { name = "Iron Lungs", detail = "Sprint twice as long", icon = "gear", price = 149, passId = 0, kind = "pass", perk = "IronLungs" },
		FeatherfallPass = { name = "Featherfall", detail = "Survive 30% higher falls", icon = "lantern", price = 199, passId = 0, kind = "pass", perk = "Featherfall" },
	},

	-- Menu sections, in order. "LIMITED" shows this week's offer.
	Categories = {
		{ id = "Featured", label = "Featured", icon = "chest", items = { "LIMITED", "DelversBundle" } },
		{ id = "Cash", label = "Coin Purses", icon = "coins", items = { "Pocket", "Purse", "HeavyPurse", "Chest", "Vault" } },
		{ id = "Gear", label = "Rope & Gear", icon = "rope", items = { "RopeLevel", "SpeedLevel", "SlotLevel" } },
		{ id = "Lanterns", label = "Lanterns", icon = "lantern", items = { "MerchantLamp", "ClimberLamp", "LuckyLantern" } },
		{ id = "Crates", label = "Relic Crates", icon = "crate", items = { "GardensCrate", "CliffsCrate", "RuinsCrate", "MarrowCrate" } },
		{ id = "Charters", label = "Charters", icon = "gear", items = { "DoubleIncomePass", "SwiftClimberPass", "IronLungsPass", "FeatherfallPass" } },
	},
}

-- Every offer is an item too, so purchases can look them up by id.
for _, offer in Config.Shop.Limited.Offers do
	offer.limited = true
	Config.Shop.Items[offer.id] = offer
end

-- Speed: the competitive stat, trained on the Hauling Rig. It only sets climb speed
-- (project owner), with diminishing returns so huge numbers stay climbable:
--   climb studs/s = BaseClimb + ClimbPerDecade x log10(1 + Speed), up to MaxClimb
-- 0 -> 16, 1K -> 52, 1M -> 88, 1B -> 124, about 1T and up -> 150. Open: numbers.
Config.Speed = {
	BaseClimb = 16,
	ClimbPerDecade = 12,
	MaxClimb = 150,
	MaxWithPerks = 240, -- after the Swift Climber pass and climb boost
	-- Climb speed also nudges walking and stamina, very slightly, with no cap (project
	-- owner): the bonus uses climb speed before MaxClimb / MaxWithPerks, so it keeps
	-- growing with Speed (slowly, on the same log curve) after climbing tops out.
	--   bonus = rate x (uncapped climb speed - BaseClimb)
	-- e.g. climb 150: +6.7% move, +10% stamina; 1Qi Speed with the pass: about +16% / +24%.
	MovePerClimb = 0.0005, -- walk and sprint speed: +0.05% per stud/s of climb speed
	StaminaPerClimb = 0.00075, -- stamina drains slower and refills faster: +0.075% per stud/s
}

-- The Hauling Rig on every base (server Hauling, client HaulController). Fully AFK
-- (project owner): the "Haul rope" prompt locks you in place at the rope, and the rig
-- pulls by itself until you move or jump. Speed per pull = PullGain x your climb speed
-- upgrade multiplier. Open: every number.
Config.Hauling = {
	PullGain = 1, -- Speed per pull, before the upgrade multiplier
	PullInterval = 0.5, -- seconds between pulls while locked in
	Range = 9, -- how close to the rope the prompt works
	StandOff = 1.25, -- haulers stand this far from the rope (matches Config.Rope.HoldOffset, so hands land on it)
	HandleHeight = 3.4, -- the handle hangs this far above the floor
	CrateSteps = 10, -- pulls to hoist the crate to the top before it drops back
}

-- Pickaxes: the weapons (project owner), one per Hollow layer, sold at the Forge (client
-- ForgeMenu, server Arsenal). A pickaxe unlocks once you have been down to its layer,
-- then costs cash (about 1.5x the rope length level that opens the layer). The
-- equipped one is your tool; swinging it hits anything tagged Tags.Enemy in reach and
-- in front of you (the server checks every swing). Creatures are later work; each base
-- has a training dummy to test on.
--   damage per hit, cooldown seconds between swings, reach studs
--   look: shaft / head colours and materials, an optional glowing accent, and a style
--   (vine, wood, stone, crystal, tide, gear, bone, ember, shroom, lumen) for the details
--   (PickaxeModels)
-- Open: every name and number.
local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
Config.Pickaxes = {
	List = {
		{ id = "Gardener", name = "Gardener's Pick", layer = 1, cost = 0, damage = 10, cooldown = 0.8, reach = 6,
			shaft = c3(130, 92, 58), shaftMaterial = Enum.Material.Wood, head = c3(150, 150, 150), headMaterial = Enum.Material.Metal, style = "vine" },
		{ id = "Rootsplitter", name = "Rootsplitter", layer = 2, cost = 22.5e3, damage = 25, cooldown = 0.75, reach = 6.5,
			shaft = c3(90, 62, 40), shaftMaterial = Enum.Material.Wood, head = c3(110, 84, 60), headMaterial = Enum.Material.Wood, style = "wood" },
		{ id = "Cliffbreaker", name = "Cliffbreaker", layer = 3, cost = 7.5e6, damage = 60, cooldown = 0.7, reach = 7,
			shaft = c3(70, 60, 54), shaftMaterial = Enum.Material.Wood, head = c3(150, 160, 170), headMaterial = Enum.Material.Slate, accent = c3(110, 170, 255), style = "stone" },
		{ id = "Frostfang", name = "Frostfang", layer = 4, cost = 4.5e9, damage = 150, cooldown = 0.65, reach = 7.5,
			shaft = c3(200, 220, 235), shaftMaterial = Enum.Material.Marble, head = c3(170, 225, 250), headMaterial = Enum.Material.Ice, accent = c3(140, 230, 255), style = "crystal" },
		{ id = "Tidecleaver", name = "Tidecleaver", layer = 5, cost = 4.5e12, damage = 400, cooldown = 0.6, reach = 8,
			shaft = c3(40, 70, 80), shaftMaterial = Enum.Material.Wood, head = c3(70, 140, 130), headMaterial = Enum.Material.CorrodedMetal, accent = c3(200, 240, 255), style = "tide" },
		{ id = "Gearbreaker", name = "Gearbreaker", layer = 6, cost = 1.5e15, damage = 1000, cooldown = 0.55, reach = 8.5,
			shaft = c3(70, 50, 34), shaftMaterial = Enum.Material.Wood, head = c3(200, 160, 80), headMaterial = Enum.Material.Metal, accent = c3(255, 190, 90), style = "gear" },
		{ id = "Marrowpick", name = "Marrowpick", layer = 7, cost = 22.5e15, damage = 2500, cooldown = 0.5, reach = 9,
			shaft = c3(220, 210, 190), shaftMaterial = Enum.Material.Marble, head = c3(236, 228, 210), headMaterial = Enum.Material.Marble, accent = c3(200, 255, 120), style = "bone" },
		{ id = "Emberhammer", name = "Emberhammer", layer = 8, cost = 375e15, damage = 6000, cooldown = 0.48, reach = 9.5,
			shaft = c3(50, 40, 38), shaftMaterial = Enum.Material.Metal, head = c3(70, 55, 50), headMaterial = Enum.Material.Basalt, accent = c3(255, 120, 40), style = "ember" },
		{ id = "Gloamreaver", name = "Gloamreaver", layer = 9, cost = 7.5e18, damage = 15000, cooldown = 0.46, reach = 10,
			shaft = c3(70, 55, 95), shaftMaterial = Enum.Material.Wood, head = c3(120, 80, 170), headMaterial = Enum.Material.Glass, accent = c3(170, 255, 225), style = "shroom" },
		{ id = "Dawnbreaker", name = "Dawnbreaker", layer = 10, cost = 150e18, damage = 37500, cooldown = 0.44, reach = 10.5,
			shaft = c3(240, 232, 215), shaftMaterial = Enum.Material.Marble, head = c3(255, 245, 220), headMaterial = Enum.Material.Foil, accent = c3(255, 225, 150), style = "lumen" },
	},
	HitDelay = 0.2, -- seconds from the swing to the hit (SwingAnimation.STRIKE)
	-- Hitting other players (project owner): no damage, but they ragdoll and fly back,
	-- so you can knock rivals away from a relic (or off a ledge). Never in town, never
	-- someone on a rope, and a short immunity after each knockdown so nobody is stun
	-- locked. Knockback grows a little with the pickaxe's layer. Open: every number.
	Pvp = {
		Enabled = true,
		Knockback = 55, -- studs/s away from the swinger
		KnockbackPerLayer = 4,
		Lift = 30, -- studs/s upward
		RagdollSeconds = 1.6,
		ImmuneSeconds = 1.5, -- after getting up
		SafeZones = { "Town" },
	},
	MaxTargets = 3, -- one swing can hit this many things
	FacingDot = 0.2, -- how far in front a target must be (1 = straight ahead)
}
-- The grappling hook (project owner), sold at the Forge (server Grapple, Arsenal). Used
-- in the Hollow, it hooks the ledge ring just above you and hauls you up onto it, for
-- when you fall below the end of your rope. One use per BandMeters of depth (0-100 m,
-- 100-200 m, ...); the bands come back in town or on respawn. Open: every number.
Config.Grapple = {
	id = "Grapple",
	name = "Grappling Hook",
	cost = 100e3,
	BandMeters = 100,
	MinRise = 6, -- the ledge must be at least this many studs above you
	PullSeconds = 1.4,
}

Config.PickaxeById = {}
for _, pickaxe in Config.Pickaxes.List do
	Config.PickaxeById[pickaxe.id] = pickaxe
end

-- Creatures of the Hollow (server Enemies, EnemyModels), one kind per layer, styled to
-- it. They roam their layer's ledges, chase players who come close (never into a
-- camp's ring, never out to the rope line), and attack in reach. Sprinting outruns them.
-- A kill pays its reward to whoever hit it last. Health is about six hits of that
-- layer's pickaxe; reward is about a minute of a Common relic from that layer.
-- Open: every name and number.
Config.Enemies = {
	PerLayer = 3, -- alive at once in each layer
	RespawnSeconds = 25,
	AggroRadius = 26, -- notices players this close on its ledge
	AggroHeight = 10, -- ...within this many studs up or down
	LeashRadius = 70, -- gives up the chase this far from where it spawned
	AttackRange = 4.5,
	SimRadius = 260, -- only creatures this close to a player move
	TickRate = 15, -- movement updates per second
	Kinds = {
		{ id = "Mosshopper", name = "Mosshopper", layer = 1, shape = "hopper", health = 60, damage = 8, attackCooldown = 1.4, speed = 13, scale = 1,
			body = Color3.fromRGB(96, 150, 70), accent = Color3.fromRGB(190, 230, 120) },
		{ id = "Barkcrawler", name = "Barkcrawler", layer = 2, shape = "crawler", health = 150, damage = 12, attackCooldown = 1.3, speed = 15, scale = 1.1,
			body = Color3.fromRGB(96, 70, 48), accent = Color3.fromRGB(230, 70, 50) },
		{ id = "SprayWraith", name = "Spray Wraith", layer = 3, shape = "wraith", health = 360, damage = 16, attackCooldown = 1.2, speed = 16, scale = 1.2,
			body = Color3.fromRGB(225, 235, 245), accent = Color3.fromRGB(120, 190, 255) },
		{ id = "Shardback", name = "Shardback", layer = 4, shape = "beetle", health = 900, damage = 22, attackCooldown = 1.2, speed = 16, scale = 1.3,
			body = Color3.fromRGB(120, 180, 210), accent = Color3.fromRGB(160, 240, 255) },
		{ id = "Murkfin", name = "Murkfin", layer = 5, shape = "fin", health = 2400, damage = 28, attackCooldown = 1.1, speed = 17, scale = 1.3,
			body = Color3.fromRGB(50, 110, 105), accent = Color3.fromRGB(255, 220, 90) },
		{ id = "Sentinel", name = "Clockwork Sentinel", layer = 6, shape = "golem", health = 6000, damage = 35, attackCooldown = 1.3, speed = 15, scale = 1.4,
			body = Color3.fromRGB(176, 140, 72), accent = Color3.fromRGB(255, 170, 60) },
		{ id = "MarrowWyrm", name = "Marrow Wyrm", layer = 7, shape = "wyrm", health = 15000, damage = 45, attackCooldown = 1.0, speed = 18, scale = 1.5,
			body = Color3.fromRGB(226, 206, 182), accent = Color3.fromRGB(190, 255, 110) },
		{ id = "Slagcrab", name = "Slagcrab", layer = 8, shape = "crab", health = 36000, damage = 55, attackCooldown = 1.1, speed = 16, scale = 1.5,
			body = Color3.fromRGB(58, 48, 44), accent = Color3.fromRGB(255, 120, 40) },
		{ id = "GloamStalker", name = "Gloam Stalker", layer = 9, shape = "stalker", health = 90000, damage = 65, attackCooldown = 1.1, speed = 17, scale = 1.5,
			body = Color3.fromRGB(110, 75, 150), accent = Color3.fromRGB(150, 255, 220) },
		{ id = "LumenSeraph", name = "Lumen Seraph", layer = 10, shape = "seraph", health = 225000, damage = 80, attackCooldown = 1.0, speed = 18, scale = 1.6,
			body = Color3.fromRGB(250, 244, 228), accent = Color3.fromRGB(255, 215, 130) },
	},
}

Config.Spawner = {
	TickSeconds = 4, -- how often each layer may refill one empty node
	-- Decided: a very rare relic has a very low chance of appearing outside its usual
	-- depth. Open: this chance and the +2 layer jump are placeholders.
	LuckyChance = 0.01,
	LuckyLayerJump = 2,
}

-- Rope progression. Each level's length is how deep (studs below rim height) the
-- player can go. Lengths line up with Config.Hollow.LayerHeight so level N reaches
-- both ledges of layer N. Open: every length, speed, and cost.
Config.Rope = {
	-- Costs follow the project owner's curve (Config.Rope.CostCurve): 15K, 250K, 5M,
	-- 120M, 3B, 75B, 3T, 50T, 1Qa, 15Qa, continued for layers 8-10 (250Qa, 5Qi,
	-- 100Qi). Each level reaches the next ledge or layer down (ledges sit at 56 and 124
	-- studs into every 160-stud layer), and the last reaches the floor of layer 10.
	LengthLevels = {
		{ value = 140, cost = 0 }, -- layer 1, both ledges
		{ value = 230, cost = 15e3 }, -- layer 2, first ledge
		{ value = 300, cost = 250e3 }, -- layer 2, both
		{ value = 390, cost = 5e6 }, -- layer 3, first ledge
		{ value = 460, cost = 120e6 }, -- layer 3, both
		{ value = 550, cost = 3e9 }, -- layer 4, first ledge
		{ value = 620, cost = 75e9 }, -- layer 4, both
		{ value = 710, cost = 3e12 }, -- layer 5, first ledge
		{ value = 780, cost = 50e12 }, -- layer 5, both
		{ value = 940, cost = 1e15 }, -- layer 6
		{ value = 1120, cost = 15e15 }, -- layer 7, to its floor
		{ value = 1270, cost = 250e15 }, -- layer 8, both ledges
		{ value = 1440, cost = 5e18 }, -- layer 9, both ledges
		{ value = 1597, cost = 100e18 }, -- layer 10, down to the floor (a climber's feet touch it)
	},
	-- The "Climb speed" upgrade (project owner): it no longer sets climb speed. Each level
	-- multiplies the Speed you gain per pull on your base's Hauling Rig (Config.Hauling);
	-- Speed is what sets climb speed (Config.Speed). Same cost curve as rope length.
	SpeedLevels = {
		{ value = 1, cost = 0 },
		{ value = 3, cost = 15e3 },
		{ value = 10, cost = 250e3 },
		{ value = 30, cost = 5e6 },
		{ value = 100, cost = 120e6 },
		{ value = 300, cost = 3e9 },
		{ value = 1000, cost = 75e9 },
		{ value = 3000, cost = 3e12 },
		{ value = 10e3, cost = 50e12 },
		{ value = 30e3, cost = 1e15 },
		{ value = 100e3, cost = 15e15 },
		{ value = 300e3, cost = 250e15 },
		{ value = 1e6, cost = 5e18 },
		{ value = 3e6, cost = 100e18 },
	},
	DescendMultiplier = 1.5, -- sliding down is faster than climbing up
	MountDepth = 3, -- players mount the rope this far below rim height
	TopOffset = 2, -- climbing ends this far above rim height; reaching it dismounts
	TopReach = 1.5, -- within this many studs of the top counts as reaching it
	ServerTopReach = 6, -- server tolerance for a top request (allows for network lag)
	HoldOffset = 1.2, -- climbers hang this far out from the rope, so it runs in front of the chest
	GrabRadius = 10, -- client hint distance for grabbing your rope from a ledge
	ServerGrabRadius = 14,
	MaxHorizontalDrift = 8, -- server: how far a climber may sit from the rope line
	SpeedTolerance = 1.6, -- server: allowed speed multiple before a snap-back
	SpeedSlack = 8, -- server: extra studs allowed per check for latency bursts
	CheckInterval = 0.1,
	DeploySeconds = 1.2, -- rope extension animation
	-- Every rope is deployed when its owner joins (project owner). Anyone may grab
	-- anyone's rope, but on someone else's rope you can only climb up (UpOnlySlack
	-- studs of give before the server holds you).
	AutoDeploy = true,
	UpOnlySlack = 3,
	-- Abseil animations (client RopePose). Leave empty to use the built-in ones
	-- (shared RopeAnimations, registered at runtime, no publishing needed). Optional:
	-- published ids ("rbxassetid://123...") override them: Hang (still on the rope),
	-- Descend (sliding down), Climb (going up). See RopeAnimations for how to publish.
	Animations = {
		Hang = "",
		Descend = "",
		Climb = "",
	},
}

-- Open: slot counts and costs.
Config.Base = {
	-- One more display per level. Costs are the rope curve at 25% less (project owner).
	SlotLevels = {
		{ value = 3, cost = 0 },
		{ value = 4, cost = 11.25e3 },
		{ value = 5, cost = 187.5e3 },
		{ value = 6, cost = 3.75e6 },
		{ value = 7, cost = 90e6 },
		{ value = 8, cost = 2.25e9 },
		{ value = 9, cost = 56.25e9 },
		{ value = 10, cost = 2.25e12 },
		{ value = 11, cost = 37.5e12 },
		{ value = 12, cost = 750e12 },
		{ value = 13, cost = 11.25e15 },
	},
	PedestalCount = 13, -- physical pedestals per plot; must cover the top slot level
	InteractMaxDistance = 14, -- server range check for plot prompts
	UpgradeClickDistance = 30, -- server range check for clicking an upgrade board
}

-- Passive income from displayed relics. Uses only information visible before
-- appraisal (type, rarity, layer found), so income never leaks hidden traits.
-- Open: all values.
Config.Income = {
	TickSeconds = 1,
}

Config.Plots = {
	Count = 8, -- also set Game Settings > Places > Max Players to 8
	Radius = 158, -- plot centres sit this far from the pit centre
	Size = 52,
}

Config.Data = {
	StoreName = "HollowboundPlayer_v1",
	KeyPrefix = "Player_",
}

Config.Pickup = {
	GroundClearance = 1.6, -- relics float this far above the real ground (grass hides lower)
	PromptMaxDistance = 8, -- client-side prompt visibility
	ServerMaxDistance = 12, -- server check; a little slack for latency
	HoldDuration = 0.3,
}

Config.Registration = {
	PromptMaxDistance = 10,
	ServerMaxDistance = 14,
	HoldDuration = 0.5,
}

Config.Zones = {
	CheckInterval = 0.25, -- seconds between server position checks
}

-- CollectionService tags. Hand-built geometry can use these tags instead of the dev map.
Config.Tags = {
	RelicSpawn = "HB_RelicSpawn", -- attribute Layer = 1..7
	WorldRelic = "HB_WorldRelic",
	RegistrationTerminal = "HB_RegistrationTerminal",
	TownZone = "HB_TownZone",
	CampZone = "HB_CampZone",
	HollowRim = "HB_HollowRim", -- one part: position = pit centre at rim height
	Plot = "HB_Plot", -- Model with attribute PlotIndex; see README for child names
	Enemy = "HB_Enemy", -- Model with a Humanoid and HumanoidRootPart that pickaxes can hit
	Spin = "HB_Spin", -- relic models clients slowly spin and bob (attribute HB_Base = rest CFrame)
}

-- Development-only switches. All of these only take effect inside Roblox Studio.
-- Admin chat commands for playtests on live servers (server Admin): "/hb help". The
-- experience owner (or rank 255 in the owning group) is always an admin, as is anyone
-- in Studio. Add friends' user ids here to let them use the commands too.
Config.Admin = {
	UserIds = {} :: { number },
}

Config.Dev = {
	BuildPlaceholderMap = true, -- build the rim town and the Hollow at runtime
	-- Also build it on live Roblox servers (each server builds it on start, about a minute
	-- for the terrain), so a published place needs no baking. Turn off once the map is
	-- baked into the place or hand-built.
	BuildMapOnLiveServers = true,
	SurfaceLighting = true, -- warm late-afternoon light and haze at the surface (dev map look)
	RunSelfTest = true, -- run the logic self-test on server start
	EnableDevRemotes = true, -- create the dev remotes (pickup tests, cash grant)
	LogTraitsToServerOutput = false, -- print hidden traits in server Output (never sent to clients)
	TimedPickupInterval = 5, -- seconds; dev key J fires on the next multiple of this server time
	CashGrant = 10000, -- dev key M
}

return Config
