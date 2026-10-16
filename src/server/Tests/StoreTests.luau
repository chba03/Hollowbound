--[[
	Store rules: milestone 1-2 regression (generation, competing claims, registration,
	death, recovery, service) plus milestone 3 state independence and loadouts.
	Pure in-memory; no storage involved.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local LoadoutRules = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("LoadoutRules"))
local RelicDefs = require(Server.RelicDefs)
local RelicStore = require(Server.RelicStore)
local SpecimenFactory = require(Server.SpecimenFactory)
local TestKit = require(script.Parent.TestKit)

local function sameTraits(a, b): boolean
	for key, value in a.traits do
		if b.traits[key] ~= value then
			return false
		end
	end
	return true
end

-- Everything except one named state, for independence checks.
local function statesExcept(specimen, except: string): string
	local parts = { RelicStore.fingerprint(specimen) }
	for _, key in { "registered", "appraised", "activated", "needsService", "charges", "condition" } do
		if key ~= except then
			table.insert(parts, `{key}={specimen[key]}`)
		end
	end
	return table.concat(parts, "|")
end

return function()
	local t = TestKit.suite("Store")
	local check = t.check
	local makeId = TestKit.idMaker("store")
	local rng = Random.new(12345)
	local store = RelicStore.new(function()
		return 0
	end)
	local rules = LoadoutRules.forStore()

	-- Milestone 1: generation, ownership, registration
	local a = SpecimenFactory.create("Windhook", 0.15, 0.33, rng, makeId)
	local b = SpecimenFactory.create("Windhook", 0.70, 0.88, rng, makeId)
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
	check(a.charges == RelicDefs.maxCharges("Windhook"), "new specimen starts with full charges")

	local ok1 = store:claim(b.id, 1)
	local ok2, reason2 = store:claim(b.id, 2)
	check(ok1 == true and ok2 == false and reason2 == "AlreadyOwned", "competing claims: exactly one player gets the specimen")
	check(#store:carried(1) == 1 and #store:carried(2) == 0, "only the winner carries it")
	check(store:claim("missing", 1) == false, "unknown specimen cannot be claimed")

	local fingerprint = RelicStore.fingerprint(b)
	local newly, already = store:registerCarried(1)
	check(#newly == 1 and #already == 0 and b.registered, "first registration secures the relic")
	local newly2, already2 = store:registerCarried(1)
	check(#newly2 == 0 and #already2 == 1 and #store:carried(1) == 1, "repeat registration registers and duplicates nothing")
	check(store:get(b.id) == b and RelicStore.fingerprint(b) == fingerprint, "registration keeps ID and traits")
	check(not b.appraised and not b.activated, "registration does not appraise or activate")

	-- Milestone 2: death, recovery, service
	check(store:claim(a.id, 1) == true, "player 1 picks up a second specimen")
	a.appraised = true -- set directly to prove death keeps it
	local aState = RelicStore.identityAndStates(a)
	local bState = RelicStore.identityAndStates(b)
	local dropped, protected = store:processDeath(1, 0, 0)
	check(#dropped == 1 and dropped[1] == a and #protected == 1 and protected[1] == b, "death drops unregistered, protects registered")
	check(a.ownerUserId == nil and a.location == "World", "dropped relic has no owner and is in the world")
	check(RelicStore.identityAndStates(a) == aState and a.charges == RelicDefs.maxCharges("Windhook"), "dropped relic keeps ID, traits, states, and charges")
	check(b.ownerUserId == 1 and b.location == "Carried" and b.needsService and b.charges == 0, "protected relic stays owned, needs service, charges emptied")
	check(RelicStore.identityAndStates(b) == bState, "protected relic keeps ID, traits, and states")
	local dropped2, protected2 = store:processDeath(1, 0, 0)
	check(#dropped2 == 0 and #protected2 == 1 and #store:carried(1) == 1, "repeated death processing changes nothing")

	local okB, reasonB = store:claim(b.id, 2)
	check(okB == false and reasonB == "AlreadyOwned", "protected relic cannot be looted by another player")
	local rec2 = store:claim(a.id, 2)
	local rec1, recReason = store:claim(a.id, 1)
	check(rec2 == true and rec1 == false and recReason == "AlreadyOwned", "competing recovery: exactly one player gets the dropped relic")
	check(RelicStore.identityAndStates(a) == aState, "recovered relic is the original specimen")
	local newly3 = store:registerCarried(2)
	check(#newly3 == 1 and newly3[1] == a and a.ownerUserId == 2, "the recovering player can register the original specimen")

	store:registerCarried(1)
	check(b.needsService and b.charges == 0, "registration does not clear Needs service or refill charges")
	check(select(2, store:service(2, b.id, 1, 3)) == "NotOwner", "another player cannot service my relic")
	check(select(2, store:service(2, a.id, 1, 3)) == "NotNeeded", "a relic in full condition is refused")
	local svc = store:service(1, b.id, 1, 3)
	check(svc == true and not b.needsService and b.condition == 1 and b.charges == 3, "service clears Needs service and refills charges")
	check(RelicStore.identityAndStates(b) == bState, "service keeps ID, traits, registration, appraisal, activation")
	check(select(2, store:service(1, b.id, 1, 3)) == "NotNeeded" and #store:carried(1) == 1, "repeated service changes nothing")

	-- Milestone 3: appraisal, activation, registration, and service stay independent
	local w = SpecimenFactory.create("Windhook", 0.5, 0.6, rng, makeId)
	store:add(w)
	store:claim(w.id, 5)
	local before = statesExcept(w, "appraised")
	check(store:appraise(5, w.id) == true and w.appraised, "appraisal reveals")
	check(statesExcept(w, "appraised") == before, "appraisal changes nothing else")
	check(select(2, store:appraise(5, w.id)) == "AlreadyAppraised", "appraising twice is refused")
	check(select(2, store:appraise(6, w.id)) == "NotOwner", "only the owner can appraise")

	before = statesExcept(w, "activated")
	check(store:activate(5, w.id, true) == true and w.activated, "activation enables")
	check(statesExcept(w, "activated") == before, "activation changes nothing else")
	check(select(2, store:activate(5, w.id, true)) == "AlreadyActivated", "activating twice is refused")

	local lens = SpecimenFactory.create("EchoLens", 0.4, 0.6, rng, makeId)
	store:add(lens)
	store:claim(lens.id, 5)
	check(lens.activated and not lens.appraised, "Echo Lens works immediately but is still unappraised")
	check(select(2, store:activate(5, lens.id, false)) == "ActivationNotRequired", "Echo Lens does not take activation")

	before = statesExcept(w, "registered")
	store:registerCarried(5)
	check(w.registered and statesExcept(w, "registered") == before, "registration changes nothing else")

	w.charges = 1
	before = statesExcept(w, "charges")
	check(store:service(5, w.id, 1, 3) == true and w.charges == 3, "service recharges a relic that is only low on charges")
	check(statesExcept(w, "charges") == before, "recharging changes nothing else")

	-- Loadout: 3 slots, at most one exceptional, no duplicates, forged requests fail
	local u = 20
	local c1 = SpecimenFactory.create("Windhook", 0.10, 0.20, rng, makeId) -- Common
	local e1 = SpecimenFactory.create("Windhook", 0.95, 0.99, rng, makeId) -- Exceptional
	local e2 = SpecimenFactory.create("EchoLens", 0.95, 0.99, rng, makeId) -- Exceptional
	local s1 = SpecimenFactory.create("EchoLens", 0.40, 0.60, rng, makeId) -- Uncommon
	for _, specimen in { c1, e1, e2, s1 } do
		store:add(specimen)
		store:claim(specimen.id, u)
	end
	check(e1.rarity == "Exceptional" and e2.rarity == "Exceptional" and c1.rarity == "Common", "test rarities are as expected")
	check(store:equip(u, e1.id, 1, rules) == true, "equip one exceptional")
	check(select(2, store:equip(u, e2.id, 2, rules)) == "ClassLimit", "a second exceptional is refused")
	local swapOk, _, replaced = store:equip(u, e2.id, 1, rules)
	check(swapOk == true and replaced == e1.id, "swapping exceptionals in the same slot works")
	check(select(2, store:equip(u, e1.id, 3, rules)) == "ClassLimit", "the swapped-out exceptional cannot join a second slot")
	check(store:equip(u, c1.id, 2, rules) == true and store:equip(u, s1.id, 3, rules) == true, "support relics fill the other slots")
	check(select(2, store:equip(u, c1.id, 3, rules)) == "AlreadyEquipped", "one relic cannot fill two slots")
	for _, badSlot in { 0, 4, 1.5, "1", 0 / 0 } do
		check(select(2, store:equip(u, e1.id, badSlot, rules)) == "BadSlot", `bad slot {tostring(badSlot)} is refused`)
	end
	check(select(2, store:equip(u, e1.id, nil, rules)) == "BadSlot", "missing slot is refused")
	check(select(2, store:equip(u, w.id, 1, rules)) == "NotOwner", "equipping another player's relic is refused")
	check(select(2, store:equip(u, "forged-id", 1, rules)) == "NotFound", "equipping a made-up ID is refused")
	check(select(2, store:equip(u, 42, 1, rules)) == "NotFound", "equipping a non-string ID is refused")
	local unOk, _, removed = store:unequip(u, 3, rules)
	check(unOk == true and removed == s1.id and store:equippedIn(u, 3) == nil, "unequip empties the slot")
	check(select(2, store:unequip(u, 3, rules)) == "SlotEmpty", "unequipping an empty slot is refused")

	-- Death unequips dropped relics; protected ones stay equipped
	store:registerCarried(u) -- e2, c1, e1, s1 are now registered
	local fresh = SpecimenFactory.create("EchoLens", 0.4, 0.6, rng, makeId)
	store:add(fresh)
	store:claim(fresh.id, u)
	store:equip(u, fresh.id, 3, rules)
	local _, _, unequipped = store:processDeath(u, 0, 0)
	check(#unequipped == 1 and unequipped[1] == fresh.id and store:equippedIn(u, 3) == nil, "death unequips the dropped relic")
	check(store:equippedIn(u, 1) == e2.id, "protected relics stay equipped")

	-- forget removes this server's copy
	local removedList = store:forget(u)
	check(#removedList == 4 and store:get(e1.id) == nil and #store:carried(u) == 0, "forget removes the player's relics and loadout")

	return t
end
