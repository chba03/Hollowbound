--[[
	Persistence rules against MockBackend (TEST-ONLY, in-memory, no DataStore access).
	Each "server" here is its own RelicStore + Sessions sharing one mock backend, which
	stands in for the shared DataStore. These tests check Sessions' rules; they do not
	prove real DataStore behaviour (see docs/TESTING.md, real-account tests).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local LoadoutRules = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("LoadoutRules"))
local MockBackend = require(Server.MockBackend)
local RelicStore = require(Server.RelicStore)
local Sessions = require(Server.Sessions)
local SpecimenCodec = require(Server.SpecimenCodec)
local SpecimenFactory = require(Server.SpecimenFactory)
local TestKit = require(script.Parent.TestKit)

local SCHEMA = 1
local PREFIX = "Test_"

local function never()
	return false
end

local function count(map): number
	local n = 0
	for _ in map or {} do
		n += 1
	end
	return n
end

return function()
	local t = TestKit.suite("Persistence")
	local check = t.check
	local makeId = TestKit.idMaker("persist")
	local rng = Random.new(4242)
	local rules = LoadoutRules.forStore()
	local backend = MockBackend.new(Sessions.template(SCHEMA))
	local clock = { now = 5000 }

	-- One simulated server.
	local function server()
		local world = { lost = {} }
		world.store = RelicStore.new(function()
			return 0
		end)
		world.sessions = Sessions.new({
			backend = backend,
			store = world.store,
			schemaVersion = SCHEMA,
			keyPrefix = PREFIX,
			now = function()
				return clock.now
			end,
			onLost = function(userId)
				world.lost[userId] = true
			end,
			log = function() end,
			warn = function() end,
		})
		return world
	end

	local function give(world, userId: number, typeId: string, qMin: number, qMax: number)
		local specimen = SpecimenFactory.create(typeId, qMin, qMax, rng, makeId)
		world.store:add(specimen)
		world.store:claim(specimen.id, userId)
		return specimen
	end

	-- 1. Same specimen and states survive leave/rejoin and a server restart.
	local s1 = server()
	check(select(1, s1.sessions:canMutate(1)) == false, "mutations are refused before the profile loads")
	check(s1.sessions:load(1, never, rules) == true, "a new player gets the template profile")
	local hook = give(s1, 1, "Windhook", 0.95, 0.99)
	s1.store:appraise(1, hook.id)
	s1.store:activate(1, hook.id, true)
	s1.store:registerCarried(1)
	s1.store:equip(1, hook.id, 1, rules)
	hook.charges = 2
	s1.sessions:setCooldown(1, "Windhook", clock.now + 30)
	local identity = RelicStore.fingerprint(hook)
	s1.sessions:commit(1, true)
	check(s1.sessions:status(1).state == "Saved", "an important commit is confirmed after the save")
	check(count(backend.saved[PREFIX .. "1"].Relics) == 1, "the registered relic is in the saved profile")
	s1.sessions:depart(1)
	check(s1.store:get(hook.id) == nil, "leaving removes the relic from server memory")

	check(s1.sessions:load(1, never, rules) == true, "rejoining the same server loads again")
	local again = s1.store:get(hook.id)
	check(again ~= nil and RelicStore.fingerprint(again) == identity, "rejoin restores the same ID, type, rarity, and traits")
	check(again.appraised and again.activated and again.registered and again.charges == 2, "rejoin restores appraisal, activation, registration, and charges")
	check(s1.store:equippedIn(1, 1) == hook.id, "rejoin restores the registered loadout")
	check(s1.sessions:cooldownDeadline(1, "Windhook") == clock.now + 30, "rejoin restores the saved cooldown deadline")
	check(#s1.store:carried(1) == 1, "rejoin creates no duplicate")
	s1.sessions:depart(1)

	local s2 = server() -- a fresh server: nothing in memory
	check(s2.sessions:load(1, never, rules) == true, "a restarted server loads the profile")
	local restarted = s2.store:get(hook.id)
	check(restarted ~= nil and RelicStore.fingerprint(restarted) == identity, "restart restores the same specimen")
	check(not pcall(function()
		restarted.traits.reach = 1
	end), "restored traits stay frozen")
	s2.sessions:depart(1)

	-- 2. Only registered relics persist; unregistered loot cannot be banked by leaving.
	local s3 = server()
	s3.sessions:load(2, never, rules)
	local fresh = give(s3, 2, "EchoLens", 0.4, 0.6)
	s3.store:equip(2, fresh.id, 1, rules)
	s3.sessions:commit(2, true)
	check(count(backend.saved[PREFIX .. "2"].Relics) == 0, "an unregistered relic is never written")
	check(count(backend.saved[PREFIX .. "2"].Loadout) == 0, "an unregistered relic is never saved in the loadout")

	-- 3. Death drops the original specimen; another player recovers and registers it;
	--    the former owner cannot get it back by rejoining.
	s3.store:processDeath(2, 0, 0)
	s3.sessions:load(3, never, rules)
	check(s3.store:claim(fresh.id, 3) == true, "another player recovers the dropped original")
	s3.store:registerCarried(3)
	s3.sessions:commit(3, true)
	s3.sessions:depart(2)
	s3.sessions:load(2, never, rules)
	check(#s3.store:carried(2) == 0, "the former owner gets nothing back by rejoining")
	check(backend.saved[PREFIX .. "3"].Relics[fresh.id] ~= nil, "the recovering player's profile holds it")
	-- Even if an old copy of the former owner's data listed it, it is not duplicated.
	s3.sessions:depart(2)
	local forged = SpecimenCodec.encode(fresh)
	forged.ownerUserId = 2
	backend.saved[PREFIX .. "2"].Relics[fresh.id] = forged
	s3.sessions:load(2, never, rules)
	check(s3.store:get(fresh.id).ownerUserId == 3 and #s3.store:carried(2) == 0, "a stale record cannot recreate a relic someone else holds")
	check(backend.saved[PREFIX .. "2"].Relics[fresh.id] ~= nil, "that record is kept untouched (quarantine), not deleted")
	s3.sessions:depart(2)
	s3.sessions:depart(3)

	-- 4. Registered relics survive death needing service and cannot be looted.
	local s4 = server()
	s4.sessions:load(4, never, rules)
	local kept = give(s4, 4, "Windhook", 0.5, 0.6)
	s4.store:registerCarried(4)
	s4.store:processDeath(4, 0, 0)
	s4.sessions:commit(4, true)
	check(select(2, s4.store:claim(kept.id, 5)) == "AlreadyOwned", "a protected relic cannot be looted")
	s4.sessions:depart(4)
	s4.sessions:load(4, never, rules)
	local back = s4.store:get(kept.id)
	check(back and back.needsService and back.charges == 0 and back.ownerUserId == 4, "after rejoin it still needs service")
	s4.sessions:depart(4)

	-- 5. A failed load never becomes a blank profile and never overwrites saved data.
	local savedBefore = backend.saved[PREFIX .. "4"]
	local revisionBefore = savedBefore.Revision
	backend.failLoads = 1
	local s5 = server()
	local loaded, err = s5.sessions:load(4, never, rules)
	check(loaded == false and err ~= nil, "a failed load reports an error")
	check(select(1, s5.sessions:canMutate(4)) == false, "mutations stay blocked after a failed load")
	check(s5.sessions:commit(4, true) == false, "a failed session cannot write")
	s5.sessions:depart(4)
	check(backend.saved[PREFIX .. "4"].Revision == revisionBefore and count(backend.saved[PREFIX .. "4"].Relics) == 1, "the saved profile is unchanged")
	check(s5.sessions:load(4, never, rules) == true and s5.store:get(kept.id) ~= nil, "the next load succeeds with the data intact")
	s5.sessions:depart(4)

	-- 6. Failed saves keep state and report it; confirmation follows the next success.
	local s6 = server()
	s6.sessions:load(6, never, rules)
	give(s6, 6, "EchoLens", 0.4, 0.6)
	s6.store:registerCarried(6)
	backend.failSaves = true
	s6.sessions:commit(6, true)
	check(s6.sessions:status(6).state == "Retrying", "a failed save is shown, not reported as saved")
	check(backend.saved[PREFIX .. "6"] == nil or count(backend.saved[PREFIX .. "6"].Relics) == 0, "nothing was written by the failed save")
	backend.failSaves = false
	s6.sessions:commit(6, true)
	check(s6.sessions:status(6).state == "Saved" and count(backend.saved[PREFIX .. "6"].Relics) == 1, "the next save succeeds")

	-- 7. Late or out-of-order save callbacks never roll confirmation back.
	backend.deferCallbacks = true
	s6.sessions:commit(6, true)
	local first = s6.sessions:entry(6).revision
	s6.sessions:commit(6, true)
	local second = s6.sessions:entry(6).revision
	check(s6.sessions:status(6).state == "Saving", "saving is shown until storage confirms")
	backend:flushCallbacks("reverse") -- newest confirmation first, the older one arrives late
	backend.deferCallbacks = false
	local entry6 = s6.sessions:entry(6)
	check(second > first and entry6.confirmedRevision == second, "a late older callback does not lower the confirmed revision")
	check(s6.sessions:status(6).state == "Saved", "status is Saved after both callbacks")

	-- 8. Competing sessions: a second server takes the profile; the first stops cleanly.
	local s7 = server()
	check(s7.sessions:load(6, never, rules) == true, "a second server can take the session")
	check(s6.lost[6] == true and s6.sessions:entry(6).state == "Lost", "the first server learns its session was lost")
	check(select(1, s6.sessions:canMutate(6)) == false, "the first server refuses further mutations")
	check(#s6.store:carried(6) == 0, "the first server drops its copy, so the relic is never in two places")
	check(s6.sessions:commit(6, true) == false, "the first server can no longer write")
	check(#s7.store:carried(6) == 1, "the second server has the relic exactly once")
	s6.sessions:depart(6) -- lost session: no save
	s7.sessions:depart(6)

	-- 9. Repeated departures and commits are harmless.
	local s8 = server()
	s8.sessions:load(8, never, rules)
	give(s8, 8, "Windhook", 0.4, 0.5)
	s8.store:registerCarried(8)
	s8.sessions:depart(8)
	local saves = backend.saveCount
	s8.sessions:depart(8)
	check(backend.saveCount == saves and s8.sessions:commit(8, true) == false, "a second departure does nothing")
	check(count(backend.saved[PREFIX .. "8"].Relics) == 1, "the relic was saved exactly once")

	-- 10. Data from a newer schema is refused and left untouched.
	backend.saved[PREFIX .. "9"] = { SchemaVersion = SCHEMA + 1, Revision = 7, Relics = { future = { id = "future" } }, Loadout = {}, Cooldowns = {} }
	local s9 = server()
	check(s9.sessions:load(9, never, rules) == false, "a newer schema is not loaded")
	check(backend.saved[PREFIX .. "9"].SchemaVersion == SCHEMA + 1 and backend.saved[PREFIX .. "9"].Relics.future ~= nil, "newer data is not overwritten")
	s9.sessions:depart(9)

	-- 11. Unreadable records stay saved; the anti-wipe guard keeps missing relics.
	backend.saved[PREFIX .. "10"] = {
		SchemaVersion = SCHEMA,
		Revision = 1,
		Relics = { odd = { v = 1, id = "odd", ownerUserId = 10, typeId = "NotAType", registered = true, rarity = "Common", traits = {} } },
		Loadout = {},
		Cooldowns = {},
	}
	local s10 = server()
	s10.sessions:load(10, never, rules)
	local keep = give(s10, 10, "Windhook", 0.4, 0.5)
	s10.store:registerCarried(10)
	s10.sessions:commit(10, true)
	check(backend.saved[PREFIX .. "10"].Relics.odd ~= nil, "an unreadable record is preserved through saves")
	s10.store.specimens[keep.id] = nil -- simulate a bug losing the live copy
	s10.sessions:commit(10, true)
	check(backend.saved[PREFIX .. "10"].Relics[keep.id] ~= nil, "a commit never deletes a saved relic")
	s10.sessions:depart(10)

	-- 12. Migration is deterministic and never invents values.
	local legacy = { v = 1, id = "legacy", ownerUserId = 11, typeId = "Windhook", registered = true, rarity = "Rare", quality = 0.7, traits = { reach = 44, cargoSupport = 0.6, efficiency = 0.5 }, charge = 0.5 }
	local d1 = SpecimenCodec.decode("legacy", legacy, 11)
	local d2 = SpecimenCodec.decode("legacy", legacy, 11)
	check(d1 and d2 and RelicStore.fingerprint(d1) == RelicStore.fingerprint(d2), "decoding the same record twice gives the same specimen")
	check(d1.charges == 2 and d1.activated == false and d1.appraised == false and d1.condition == 1, "missing fields get fixed defaults")
	check(d1.traits.reach == 44 and d1.rarity == "Rare", "traits and rarity come only from the record")
	check(SpecimenCodec.decode("legacy", legacy, 12) == nil, "a record cannot load into another player's profile")
	check(SpecimenCodec.decode("other", legacy, 11) == nil, "a record must match its key")

	return t
end
