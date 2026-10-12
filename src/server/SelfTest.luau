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

	print(`[Hollowbound] Self-test finished: {total - failures}/{total} passed`)
	return failures == 0
end

return SelfTest
