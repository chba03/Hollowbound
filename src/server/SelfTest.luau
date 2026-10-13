--[[
	DEVELOPMENT ONLY. Checks the ownership, registration, display, save, plot, and
	progression rules against fresh in-memory objects at server start. It does not touch
	the live game state. Results appear in the server Output window as PASS/FAIL lines.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))
local Plots = require(script.Parent.Plots)
local RelicSpawner = require(script.Parent.RelicSpawner)
local RelicStore = require(script.Parent.RelicStore)
local SpecimenFactory = require(script.Parent.SpecimenFactory)

local SelfTest = {}

local function sameTraits(a, b): boolean
	for key, value in a.traits do
		if b.traits[key] ~= value then
			return false
		end
	end
	return true
end

function SelfTest.run(): boolean
	local total, failures = 0, 0
	local function check(condition: boolean, label: string)
		total += 1
		if condition then
			print("  PASS " .. label)
		else
			failures += 1
			warn("  FAIL " .. label)
		end
	end

	print("[Hollowbound] Self-test:")

	local counter = 0
	local function makeId()
		counter += 1
		return `test-{counter}`
	end
	local rng = Random.new(12345)
	local store = RelicStore.new(function()
		return 0
	end)

	-- Generation
	local a = SpecimenFactory.create("Windhook", 0.15, 0.35, rng, makeId)
	local b = SpecimenFactory.create("Windhook", 0.70, 0.95, rng, makeId)
	store:add(a)
	store:add(b)
	check(a.id ~= b.id, "specimens get unique IDs")
	check(not sameTraits(a, b), "test specimens have different traits")
	check(not pcall(function()
		a.traits.reach = 999
	end), "traits are frozen")
	check(not pcall(function()
		store:add({ id = a.id })
	end), "duplicate IDs are refused")
	check(not a.appraised and not a.registered and not a.activated, "new Windhook: unappraised, unregistered, needs activation")

	-- Ownership
	local ok1 = store:claim(b.id, 1)
	local ok2, reason2 = store:claim(b.id, 2)
	check(ok1 == true and ok2 == false and reason2 == "AlreadyOwned", "competing claims: exactly one player gets the specimen")
	check(#store:carried(1) == 1 and #store:carried(2) == 0, "only the winner carries it")
	check(b.ownerUserId == 1 and not b.registered, "picked-up relic is owned but unsecured")
	check(store:claim("missing", 1) == false, "unknown specimen cannot be claimed")

	-- Registration
	local fingerprint = RelicStore.fingerprint(b)
	local newly, already = store:registerCarried(1)
	check(#newly == 1 and #already == 0 and b.registered, "first registration secures the relic")
	local newly2, already2 = store:registerCarried(1)
	check(#newly2 == 0 and #already2 == 1, "repeat registration registers nothing new")
	check(#store:carried(1) == 1, "repeat registration creates no duplicate")
	check(store:get(b.id) == b and RelicStore.fingerprint(b) == fingerprint, "registration keeps ID and traits")
	check(not b.appraised and not b.activated, "registration does not appraise or activate")

	local newly3 = store:registerCarried(2)
	check(#newly3 == 0 and not a.registered, "a player cannot register relics they do not carry")

	-- Displays
	store:claim(a.id, 1) -- a: owned by player 1, unregistered
	local okU, reasonU = store:place(1, a.id, 1, 3)
	check(okU == false and reasonU == "Unregistered", "unregistered relics cannot be displayed")
	local okL, reasonL = store:place(1, b.id, 4, 3)
	check(okL == false and reasonL == "SlotLocked", "slots above capacity are locked")
	local okN, reasonN = store:place(2, b.id, 1, 3)
	check(okN == false and reasonN == "NotOwner", "players cannot display relics they do not own")
	check(store:place(1, b.id, 2, 3) == true and b.location == "Placed" and b.slot == 2, "registered relic goes on display")
	check(#store:carried(1) == 1 and #store:owned(1) == 2, "displayed relic leaves the pack but stays owned")
	local c = SpecimenFactory.create("Windhook", 0.5, 0.6, rng, makeId, 2)
	store:add(c)
	store:claim(c.id, 1)
	store:registerCarried(1) -- registers a and c
	local okT, reasonT = store:place(1, c.id, 2, 3)
	check(okT == false and reasonT == "SlotTaken", "an occupied slot refuses a second relic")
	check(store:unplace(1, 2) == b and b.location == "Carried" and b.slot == nil, "take back returns the relic to the pack")
	check(RelicStore.fingerprint(b) == fingerprint, "displaying keeps ID and traits")

	-- Saving
	local saved = SpecimenFactory.serialize(c)
	local restored = SpecimenFactory.deserialize(c.id, saved)
	check(restored ~= nil and RelicStore.fingerprint(restored) == RelicStore.fingerprint(c), "save round trip keeps ID and traits")
	check(restored ~= nil and table.isfrozen(restored.traits), "restored traits are frozen")
	check(restored ~= nil and restored.layer == 2 and restored.registered, "save round trip keeps layer and registration")
	check(SpecimenFactory.deserialize("x", { typeId = "NoSuchType", traits = {} }) == nil, "unknown saved types are skipped")

	-- Night reset
	local w = SpecimenFactory.create("Windhook", 0.1, 0.2, rng, makeId, 1)
	store:add(w)
	check(store:removeWorld(w.id) == true and store:get(w.id) == nil, "night removes relics lying in the world")
	check(store:removeWorld(b.id) == false and store:get(b.id) == b, "night never removes an owned relic")
	check(Config.Night.NightSeconds < Config.Night.CycleSeconds, "night is shorter than the whole cycle")

	-- Leaving
	local d = SpecimenFactory.create("Windhook", 0.1, 0.2, rng, makeId, 1)
	store:add(d)
	store:claim(d.id, 1)
	check(store:releasePlayer(1) == 1 and store:get(d.id) == nil and #store:owned(1) == 0, "leaving forfeits only unsecured relics from memory")

	-- Plots
	local allocator = Plots.newAllocator(Config.Plots.Count)
	local seen, distinct = {}, true
	for userId = 1, Config.Plots.Count do
		local index = allocator:claim(userId)
		if index == nil or seen[index] then
			distinct = false
		else
			seen[index] = true
		end
	end
	check(distinct, "each player gets a different plot")
	check(allocator:claim(999) == nil, "no plot when the server is full")
	check(allocator:claim(3) == 3, "claiming again returns the same plot")
	check(allocator:release(3) == 3 and allocator:claim(999) == 3, "a released plot is reassigned")

	-- Progression
	check(Progression.next("RopeLength", #Config.Rope.LengthLevels) == nil, "max rope level has no next upgrade")
	check(Progression.value("BaseSlots", 1) == Config.Base.SlotLevels[1].value, "level 1 slot count comes from Config")
	check(Progression.layerForDepth(0) == 0 and Progression.layerForDepth(1) == 1, "layer 0 at the rim, layer 1 just below")
	check(Progression.layerForDepth(1e6) == #Config.Layers, "depth clamps to the last layer")
	local rising, previous = true, 0
	for _, def in Config.Rope.LengthLevels do
		rising = rising and def.value > previous
		previous = def.value
	end
	local lengths = Config.Rope.LengthLevels
	check(rising, "each rope level is longer than the last")
	check(lengths[#lengths].value >= #Config.Layers * Config.Hollow.LayerHeight, "the longest rope reaches the floor")
	-- Relic catalogue
	-- Income range per layer and tier (nil when the layer has no relic of that tier).
	local function range(layer: number, tierId: string): (number?, number?)
		local ids = Config.RelicsByLayer[layer][tierId]
		if not ids then
			return nil, nil
		end
		local low, high = math.huge, 0
		for _, id in ids do
			local income = Progression.incomeFor(id, tierId, layer)
			low, high = math.min(low, income), math.max(high, income)
		end
		return low, high
	end
	local count, tiersGrow, layersGrow = 0, true, true
	for layer = 1, #Config.Layers do
		local previousHigh = 0
		for _, tier in Config.Rarities do
			local low, high = range(layer, tier.id)
			if not low then
				continue
			end
			if low <= previousHigh then
				tiersGrow = false
			end
			previousHigh = high :: number
			local aboveHigh: number? = nil
			if layer > 1 then
				_, aboveHigh = range(layer - 1, tier.id)
			end
			if aboveHigh and low <= aboveHigh then
				layersGrow = false
			end
		end
	end
	for _ in Config.RelicTypes do
		count += 1
	end
	local function has(layer: number, tierId: string): boolean
		return Config.RelicsByLayer[layer][tierId] ~= nil
	end
	check(count == 70 and #Config.RelicOrder == 70, "the catalogue has 70 relic types")
	check(
		not has(1, "Divine") and not has(2, "Godly") and not has(4, "Godly") and has(3, "Divine") and has(5, "Godly")
			and not has(3, "Eternal") and has(4, "Eternal") and has(10, "Eternal") and has(10, "Godly"),
		"no Divine or Godly in layers 1-2, no Godly in layers 3-4, Eternal from layer 4 down"
	)
	local everyLayerFilled = true
	for layer = 1, #Config.Layers do
		for _, tierId in { "Common", "Uncommon", "Mythic", "Secret" } do
			everyLayerFilled = everyLayerFilled and has(layer, tierId)
		end
	end
	check(everyLayerFilled, "every layer has Common to Secret relics")
	check(tiersGrow, "within a layer, each tier earns more than the one below")
	check(layersGrow, "each tier earns more one layer deeper")
	local onlyAllowed = true
	local tierRng0 = Random.new(3)
	for _ = 1, 2000 do
		local tierId = RelicSpawner.rollRarity(tierRng0, 1)
		if tierId == "Divine" or tierId == "Eternal" or tierId == "Godly" then
			onlyAllowed = false
		end
	end
	check(onlyAllowed, "layer 1 never rolls Divine, Eternal, or Godly")
	local neverNormal = true
	for _ = 1, 3000 do
		local tierId = RelicSpawner.rollRarity(tierRng0, 10)
		if Config.RarityById[tierId].rank >= 5 then
			neverNormal = false
		end
	end
	check(neverNormal, "Divine and up never come from normal refills (rare spawns only)")
	local sizes, minSize, maxSize = Random.new(9), math.huge, 0
	for _ = 1, 3000 do
		local size = SpecimenFactory.rollSize(sizes)
		minSize, maxSize = math.min(minSize, size), math.max(maxSize, size)
	end
	local bands = Config.Sizes.Bands
	check(minSize >= bands[1].min and maxSize <= bands[#bands].max and maxSize > 1.5, "sizes stay inside their bands and vary")
	check(Progression.incomeFor("Windhook", "Common", 1, 2) > Progression.incomeFor("Windhook", "Common", 1, 1), "bigger specimens earn more")
	check(Progression.relicName("FrostShard", 2.4) == "Huge Frost Shard" and Progression.relicName("FrostShard", 1) == "Frost Shard", "size words in relic names")
	local godly = SpecimenFactory.create("UnbornStar", 0.75, 1, rng, makeId, 7)
	check(godly.rarity == "Godly" and godly.quality <= 1, "a specimen's rarity is its type's tier")
	local migrated = SpecimenFactory.deserialize("old", { typeId = "Windhook", rarity = "Exceptional", traits = { reach = 30 } })
	check(
		migrated ~= nil and migrated.rarity == "Common" and migrated.traits.reach == 30 and migrated.size == 1,
		"old saves load with the new tier, the same traits, and size 1"
	)
	local seenTiers = {}
	local tierRng = Random.new(7)
	for _ = 1, 4000 do
		local tier = RelicSpawner.rollRarity(tierRng)
		seenTiers[tier] = (seenTiers[tier] or 0) + 1
	end
	check((seenTiers.Common or 0) > (seenTiers.Mythic or 0) and (seenTiers.Mythic or 0) > (seenTiers.Godly or 0), "lower tiers spawn more often")
	check(RelicSpawner.pickType(3, "Divine", tierRng) == "ThunderSpiral", "a layer's tier roll picks that layer's relic")
	check(Config.Base.PedestalCount >= Config.Base.SlotLevels[#Config.Base.SlotLevels].value, "enough pedestals for max slots")

	-- Speed
	check(Progression.climbSpeed(0) == Config.Speed.BaseClimb, "no Speed climbs at the base speed")
	check(Progression.climbSpeed(1e6) > Progression.climbSpeed(1e3), "more Speed climbs faster")
	check(Progression.climbSpeed(1e30) == Config.Speed.MaxClimb, "climb speed is capped")
	local multipliers = Config.Rope.SpeedLevels
	check(multipliers[#multipliers].value > multipliers[1].value, "climb speed upgrades raise Speed per pull")

	-- Pit shape
	local H = Config.Hollow
	local clear = true
	for depth = 0, #Config.Layers * H.LayerHeight, 4 do
		if Progression.pitRadiusAt(depth) < H.LedgeInnerRadius + 12 then
			clear = false
		end
	end
	check(clear, "the pit never narrows onto the ledges or ropes")
	check(Progression.pitRadiusAt(0) == H.PitRadius, "pit radius at the rim matches Config.Hollow.PitRadius")
	check(H.RopeRadius + 4 <= H.LedgeInnerRadius, "ropes hang clear of the ledges")
	check(H.LedgeDepths[#H.LedgeDepths] <= Config.Rope.LengthLevels[1].value, "the first rope reaches every layer 1 ledge")

	-- Spawn tables
	local alwaysLucky = { NextNumber = function()
		return 0
	end }
	local _, luckySource = RelicSpawner.rollTable(1, alwaysLucky :: any)
	check(luckySource == 1 + Config.Spawner.LuckyLayerJump, "a lucky roll uses a deeper layer's table")
	local _, normalSource = RelicSpawner.rollTable(#Config.Layers, Random.new(1))
	check(normalSource == #Config.Layers, "the last layer never rolls past itself")

	print(`[Hollowbound] Self-test finished: {total - failures}/{total} passed`)
	return failures == 0
end

return SelfTest
