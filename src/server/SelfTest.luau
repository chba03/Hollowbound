--[[
	DEVELOPMENT ONLY. Checks the ownership and registration rules against a fresh
	in-memory store at server start. It does not touch the live game state.
	Results appear in the server Output window as PASS/FAIL lines.
]]

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

	-- Final death: player 1 carries a (unregistered) and b (registered).
	check(store:claim(a.id, 1) == true, "player 1 picks up the second specimen")
	-- No appraisal or activation flow exists yet; set them here to prove death keeps them.
	a.appraised = true
	a.activated = true
	local aState = RelicStore.identityAndStates(a)
	local bState = RelicStore.identityAndStates(b)

	local dropped, protected = store:processDeath(1, 0, 0)
	check(#dropped == 1 and dropped[1] == a and #protected == 1 and protected[1] == b, "death drops unregistered, protects registered")
	check(a.ownerUserId == nil and a.location == "World", "dropped relic has no owner and is in the world")
	check(RelicStore.identityAndStates(a) == aState, "dropped relic keeps ID, traits, appraisal, activation")
	check(b.ownerUserId == 1 and b.location == "Carried" and b.needsService, "protected relic stays owned and needs service")
	check(RelicStore.identityAndStates(b) == bState, "protected relic keeps ID, traits, and states")
	check(#store:carried(1) == 1 and store:carried(1)[1] == b, "inventory after death holds only the protected relic")

	local dropped2, protected2 = store:processDeath(1, 0, 0)
	check(#dropped2 == 0 and #protected2 == 1 and #store:carried(1) == 1, "repeated death processing changes nothing")

	-- Recovery
	local okB, reasonB = store:claim(b.id, 2)
	check(okB == false and reasonB == "AlreadyOwned", "protected relic cannot be claimed by another player")
	local rec2 = store:claim(a.id, 2)
	local rec1, recReason = store:claim(a.id, 1)
	check(rec2 == true and rec1 == false and recReason == "AlreadyOwned", "competing recovery: exactly one player gets the dropped relic")
	check(#store:carried(2) == 1 and #store:carried(1) == 1, "recovery creates no duplicate")
	check(RelicStore.identityAndStates(a) == aState, "recovered relic keeps ID, traits, appraisal, activation")

	-- Service
	store:registerCarried(1)
	check(b.needsService, "registration does not clear Needs service")
	check(select(2, store:service(2, b.id, 1, 1)) == "NotOwner", "another player cannot service my relic")
	check(select(2, store:service(2, a.id, 1, 1)) == "NotNeeded", "relic that does not need service is refused")
	local svc = store:service(1, b.id, 1, 1)
	check(svc == true and not b.needsService and b.condition == 1 and b.charge == 1, "service clears Needs service and restores condition")
	check(RelicStore.identityAndStates(b) == bState, "service keeps ID, traits, registration, appraisal, activation")
	check(select(2, store:service(1, b.id, 1, 1)) == "NotNeeded" and #store:carried(1) == 1, "repeated service changes nothing")

	print(`[Hollowbound] Self-test finished: {total - failures}/{total} passed`)
	return failures == 0
end

return SelfTest
