--[[
	Provisional configuration.

	Design status labels follow docs/Hollowbound_Game_Design_v0_2.pdf:
	  Decided   - explicit design choice
	  Delegated - assistant recommendation adopted as the working direction
	  Proposed  - illustrative example, not selected
	  Open      - still needs a decision or testing
	Every number in this file is a placeholder for testing, not a balance decision.

	Milestone 2 adds the rim town (8 plots), the Hollow (7 layers), rope progression,
	relic displays with passive income, and saved player data. Those come from the
	project owner's milestone 2 brief. The design record lists displays as an Open
	"home for the collection"; rope-gated depth and passive income are new to this brief.
]]

local Config = {}

-- Rarity tiers, from the project owner's relic brief: Common, Uncommon, Mythic,
-- Secret, Divine, Godly. Every relic type belongs to exactly one tier, shown on pickup.
-- Open: tier names stay as briefed; weights, income, and colours are placeholders.
--   weight  = spawn chance relative to the other tiers in the same layer (percent);
--             layers 1-2 have no Divine or Godly relics and layers 3-4 no Godly
--   income  = base cash per second on display, before the type and layer multipliers
--   quality = bonus added to the layer's specimen quality band (better hidden traits)
--   light / sparkle / pillar / scale = how the relic shows in the world
Config.Rarities = {
	{ id = "Common", weight = 60, income = 1, quality = 0, color = Color3.fromRGB(205, 205, 205), light = 6, sparkle = 0, pillar = false, scale = 1 },
	{ id = "Uncommon", weight = 26, income = 3, quality = 0.05, color = Color3.fromRGB(100, 210, 120), light = 8, sparkle = 0, pillar = false, scale = 1.05 },
	{ id = "Mythic", weight = 10, income = 12, quality = 0.1, color = Color3.fromRGB(170, 100, 255), light = 10, sparkle = 2, pillar = false, scale = 1.15 },
	{ id = "Secret", weight = 3, income = 50, quality = 0.15, color = Color3.fromRGB(255, 70, 110), light = 12, sparkle = 4, pillar = false, scale = 1.25 },
	{ id = "Divine", weight = 0.8, income = 250, quality = 0.2, color = Color3.fromRGB(255, 215, 90), light = 14, sparkle = 8, pillar = true, scale = 1.35 },
	{ id = "Godly", weight = 0.2, income = 1500, quality = 0.25, color = Color3.fromRGB(120, 255, 235), light = 18, sparkle = 14, pillar = true, scale = 1.5 },
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
	The relic catalogue: 42 types. Layers 1-2 hold Common to Secret, layers 3-4 add
	Divine, and layers 5-7 hold every tier with two Divine and two Godly types each, so
	each step down and each tier up is worth more.
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

	-- Layer 5: Drowned Terraces
	{ "SiltTablet", "Silt Tablet", 5, "Common", 1.0, "layered", rgb(150, 140, 120), rgb(90, 85, 80), M.Slate, { "memory", "stability" }, false, "Layers of river silt pressed into stone." },
	{ "Tidecross", "Tidecross", 5, "Uncommon", 1.1, "cross", rgb(90, 75, 60), rgb(160, 200, 200), M.Wood, { "buoyancy", "ward" }, false, "Driftwood that always floats upright." },
	{ "PathfindersEye", "Pathfinder's Eye", 5, "Mythic", 1.15, "disc", rgb(120, 125, 120), rgb(70, 170, 160), M.Slate, { "sight", "clarity" }, true, "Its eye turns toward the way out." },
	{ "DrownedBell", "Drowned Bell", 5, "Secret", 1.2, "bell", rgb(70, 130, 120), rgb(200, 180, 120), M.CorrodedMetal, { "resonance", "silence" }, false, "It rings only when held under water." },
	{ "DeepwaterPearls", "Deepwater Pearls", 5, "Divine", 1.25, "beads", rgb(60, 80, 110), rgb(200, 220, 255), M.Glass, { "buoyancy", "glow", "memory" }, false, "Dark pearls with a light deep inside." },
	{ "Floodcrown", "Floodcrown", 5, "Godly", 1.3, "folded", rgb(70, 140, 150), rgb(200, 255, 245), M.Glass, { "pull", "buoyancy", "vitality" }, true, "Folded water, held in a shape it remembers." },
	{ "SunkenLantern", "Sunken Lantern", 5, "Divine", 1.35, "bell", rgb(50, 110, 105), rgb(255, 210, 120), M.CorrodedMetal, { "glow", "silence", "memory" }, false, "Still lit after centuries under the water." },
	{ "Tideheart", "Tideheart", 5, "Godly", 1.4, "ringsphere", rgb(30, 70, 120), rgb(140, 230, 255), M.Glass, { "pull", "buoyancy", "pulse" }, true, "Every terrace fills and drains to its beat." },

	-- Layer 6: Rootbound Ruins
	{ "RustedSeal", "Rusted Seal", 6, "Common", 1.0, "disc", rgb(130, 100, 80), rgb(80, 70, 60), M.CorrodedMetal, { "ward", "memory" }, false, "A stamped seal from a builder no one knows." },
	{ "RuinBrick", "Ruin Brick", 6, "Uncommon", 1.1, "layered", rgb(170, 160, 140), rgb(110, 80, 60), M.Brick, { "stability", "memory" }, false, "A brick that still remembers its wall." },
	{ "WayfarerKey", "Wayfarer Key", 6, "Mythic", 1.15, "cross", rgb(180, 160, 120), rgb(110, 80, 55), M.Wood, { "attunement", "noise" }, true, "It fits locks that are not there yet." },
	{ "RootEffigy", "Root Effigy", 6, "Secret", 1.2, "bonehook", rgb(120, 90, 60), rgb(200, 170, 120), M.Wood, { "growth", "ward" }, false, "Roots grown into the shape of a figure." },
	{ "ClockworkLattice", "Clockwork Lattice", 6, "Divine", 1.25, "coil", rgb(180, 150, 90), rgb(110, 90, 60), M.Metal, { "pulse", "stability", "memory" }, true, "Gears inside still tick, slowly, toward something." },
	{ "FoundersSeal", "Founder's Seal", 6, "Godly", 1.3, "knot", rgb(200, 170, 90), rgb(255, 235, 160), M.Foil, { "ward", "attunement", "memory" }, true, "The mark of whoever built the ruins first." },
	{ "WardensPrism", "Warden's Prism", 6, "Divine", 1.35, "prism", rgb(230, 170, 70), rgb(255, 240, 190), M.Glass, { "ward", "clarity", "glow" }, true, "It once lit the ruins' great gate." },
	{ "GearOfAges", "Gear of Ages", 6, "Godly", 1.4, "disc", rgb(205, 165, 70), rgb(120, 90, 50), M.Foil, { "pulse", "memory", "stability" }, true, "Turn it once and the ruins remember being whole." },

	-- Layer 7: The Marrow
	{ "MarrowNodule", "Marrow Nodule", 7, "Common", 1.0, "lumpball", rgb(170, 160, 140), rgb(220, 210, 190), M.Pebble, { "vitality", "pulse" }, false, "Warm, and very faintly beating." },
	{ "SporePod", "Spore Pod", 7, "Uncommon", 1.1, "spikeball", rgb(115, 95, 70), rgb(220, 210, 180), M.Pebble, { "growth", "pulse" }, false, "Shakes when something alive comes near." },
	{ "BoundSpiral", "Bound Spiral", 7, "Mythic", 1.15, "spiral", rgb(230, 225, 205), rgb(200, 255, 120), M.Marble, { "pulse", "vitality" }, false, "Bone bands bound around a green glow." },
	{ "LivingCube", "Living Cube", 7, "Secret", 1.2, "folded", rgb(110, 120, 70), rgb(200, 240, 160), M.Fabric, { "growth", "memory" }, false, "Folds and unfolds itself while you sleep." },
	{ "MarrowFang", "Marrow Fang", 7, "Divine", 1.25, "bonehook", rgb(235, 230, 215), rgb(90, 80, 70), M.Marble, { "reach", "vitality", "pull" }, true, "Grown, not carved, from something enormous." },
	{ "UnbornStar", "The Unborn Star", 7, "Godly", 1.3, "ringsphere", rgb(250, 230, 160), rgb(255, 255, 220), M.Neon, { "glow", "vitality", "attunement" }, true, "The light at the very bottom of the Hollow." },
	{ "SporeSovereign", "Spore Sovereign", 7, "Divine", 1.35, "spikeball", rgb(90, 120, 60), rgb(210, 255, 120), M.Pebble, { "growth", "vitality", "pulse" }, false, "Every spore in the Marrow leans toward it." },
	{ "Marrowheart", "Marrowheart", 7, "Godly", 1.4, "lumpball", rgb(170, 60, 60), rgb(255, 170, 120), M.Glass, { "vitality", "pulse", "warmth" }, true, "It beats. The whole Hollow beats with it." },
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
--   incomeMultiplier = display income scale for relics from that layer. Fitted by a
--              progression simulation against the rope costs so a typical player
--              (about one relic a minute, best relics on display) spends about
--              8 min in layer 1, 25 min in layer 2, 1.5 h in layer 3, 4 h in layer 4,
--              and 12 h of play in each layer after that (about 30 h to layer 7).
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
		incomeMultiplier = 2300,
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
		incomeMultiplier = 260e3,
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
		incomeMultiplier = 5.4e6,
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
		incomeMultiplier = 110e6,
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
		incomeMultiplier = 2.1e9,
		maxNodes = 4,
		radius = 124,
		fog = Color3.fromRGB(180, 150, 105),
		tint = Color3.fromRGB(255, 238, 205),
		brightness = -0.05,
		density = 0.5,
		motes = { color = Color3.fromRGB(230, 255, 140), rate = 12, size = 0.35, speed = 0.7, glow = 1 },
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
			{ id = "EmberCrate", name = "Ember Crate", detail = "A layer 7 relic, Divine or Godly odds x5", icon = "crate", price = 499, productId = 0,
				kind = "crate", layer = 7, weights = { Common = 30, Uncommon = 28, Mythic = 20, Secret = 14, Divine = 6, Godly = 2 } },
			{ id = "MidnightCache", name = "Midnight Cache", detail = "4 hours of income + a Lucky Lantern", icon = "chest", price = 399, productId = 0,
				kind = "bundle", contents = { { kind = "cash", minutes = 240, minimum = 500000 }, { kind = "serverLuck", minutes = 15 } } },
			{ id = "DelversKit", name = "Delver's Kit", detail = "+1 rope length, +1 climb speed, a layer 5 crate", icon = "rope", price = 349, productId = 0,
				kind = "bundle", contents = { { kind = "level", upgrade = "RopeLength" }, { kind = "level", upgrade = "RopeSpeed" }, { kind = "crate", layer = 5 } } },
		},
	},

	-- Crate tier odds when an item gives none (only tiers the layer holds can come up).
	CrateWeights = { Common = 45, Uncommon = 30, Mythic = 15, Secret = 7, Divine = 2.4, Godly = 0.6 },

	Items = {
		DelversBundle = { name = "Delver's Bundle", detail = "1 hour of income, +1 rope length, a layer 3 crate", icon = "chest", price = 299, productId = 0, tag = "BEST VALUE", wide = true,
			kind = "bundle", contents = { { kind = "cash", minutes = 60, minimum = 100000 }, { kind = "level", upgrade = "RopeLength" }, { kind = "crate", layer = 3 } } },

		Pocket = { name = "Pocket of Coins", icon = "coins", price = 49, productId = 0, kind = "cash", minutes = 5, minimum = 5000 },
		Purse = { name = "Coin Purse", icon = "purse", price = 99, productId = 0, kind = "cash", minutes = 15, minimum = 25000 },
		HeavyPurse = { name = "Heavy Purse", icon = "purse", price = 249, productId = 0, kind = "cash", minutes = 60, minimum = 100000 },
		Chest = { name = "Treasure Chest", icon = "chest", price = 499, productId = 0, kind = "cash", minutes = 240, minimum = 500000, wide = true },
		Vault = { name = "Guild Vault", icon = "chest", price = 799, productId = 0, kind = "cash", minutes = 720, minimum = 2000000, wide = true, tag = "MOST CASH" },

		RopeLevel = { name = "Steel-Core Rope", icon = "rope", price = 149, productId = 0, kind = "level", upgrade = "RopeLength" },
		SpeedLevel = { name = "Clockwork Winch", icon = "gear", price = 149, productId = 0, kind = "level", upgrade = "RopeSpeed" },
		SlotLevel = { name = "Extra Pedestal", icon = "gear", price = 99, productId = 0, kind = "level", upgrade = "BaseSlots" },

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
	-- 120M, 3B, 75B, 3T, 50T, 1Qa, 15Qa. Eleven levels: each one reaches the next ledge
	-- down (ledges sit at 56 and 124 studs into every 160-stud layer), and the last
	-- reaches the floor of layer 7.
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
		{ value = 1120, cost = 15e15 }, -- layer 7, to the floor
	},
	-- Climbing speed in studs per second, same cost curve.
	SpeedLevels = {
		{ value = 16, cost = 0 },
		{ value = 20, cost = 15e3 },
		{ value = 25, cost = 250e3 },
		{ value = 31, cost = 5e6 },
		{ value = 38, cost = 120e6 },
		{ value = 46, cost = 3e9 },
		{ value = 55, cost = 75e9 },
		{ value = 65, cost = 3e12 },
		{ value = 76, cost = 50e12 },
		{ value = 88, cost = 1e15 },
		{ value = 100, cost = 15e15 },
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
	Spin = "HB_Spin", -- relic models clients slowly spin and bob (attribute HB_Base = rest CFrame)
}

-- Development-only switches. All of these only take effect inside Roblox Studio.
Config.Dev = {
	BuildPlaceholderMap = true, -- build the rim town and the Hollow at runtime
	SurfaceLighting = true, -- warm late-afternoon light and haze at the surface (dev map look)
	RunSelfTest = true, -- run the logic self-test on server start
	EnableDevRemotes = true, -- create the dev remotes (pickup tests, cash grant)
	LogTraitsToServerOutput = false, -- print hidden traits in server Output (never sent to clients)
	TimedPickupInterval = 5, -- seconds; dev key J fires on the next multiple of this server time
	CashGrant = 10000, -- dev key M
}

return Config
