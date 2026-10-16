--[[
	Milestone 4 creature and encounter rules: the shared brain for both variants,
	telegraph and opening, leash and reset, protected zones, downed targets, guardian
	rewards (exactly once per cycle), and melee hit selection. Pure modules; fake clock.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local CreatureBrain = require(Server.CreatureBrain)
local EncounterCore = require(Server.EncounterCore)
local MeleeRules = require(Server.MeleeRules)
local RelicStore = require(Server.RelicStore)
local SpecimenFactory = require(Server.SpecimenFactory)
local TestKit = require(script.Parent.TestKit)

local function v3(x, y, z)
	return { X = x, Y = y, Z = z }
end

local function perception(now, targets, extra)
	local p = { now = now, distanceFromHome = 0, selfProtected = false, patrolArrived = false, pathFailures = 0, targets = targets }
	for k, val in extra or {} do
		p[k] = val
	end
	return p
end

local function target(distance, extra)
	local t = { distance = distance, visible = true, noticeable = true, protected = false, condition = "Alive", homeDistance = distance }
	for k, val in extra or {} do
		t[k] = val
	end
	return t
end

return function()
	local t = TestKit.suite("Creatures")
	local check = t.check
	local regular = Config.Creatures.Variants.Regular
	local guardian = Config.Creatures.Variants.Guardian

	check(guardian.recovery > regular.recovery and guardian.windup > regular.windup, "the guardian has a longer telegraph and a clear opening")

	-- Detection, pursuit, telegraph, strike, recovery.
	local c = CreatureBrain.new(0)
	local d = CreatureBrain.step(c, perception(0, { p1 = target(30, { noticeable = false }) }), regular)
	check(c.state == "Idle" and d.move == "Stop", "an unnoticed explorer is not chased")
	d = CreatureBrain.step(c, perception(0.2, { p1 = target(30) }), regular)
	check(c.state == "Pursue" and c.targetKey == "p1" and d.move == "Target", "a noticed explorer is pursued")
	d = CreatureBrain.step(c, perception(0.4, { p1 = target(regular.attackRange - 1) }), regular)
	check(c.state == "Windup" and d.telegraph == true and d.move == "Stop", "in range: the attack is telegraphed first")
	d = CreatureBrain.step(c, perception(0.4 + regular.windup / 2, { p1 = target(2) }), regular)
	check(not d.strike and c.state == "Windup", "no strike before the telegraph ends")
	d = CreatureBrain.step(c, perception(0.4 + regular.windup + 0.01, { p1 = target(2) }), regular)
	check(d.strike == true and c.state == "Recover", "the strike follows the telegraph")
	d = CreatureBrain.step(c, perception(0.5 + regular.windup, { p1 = target(2) }), regular)
	check(d.move == "Stop" and not d.strike and c.state == "Recover", "recovery is an opening: no movement, no strike")

	-- Downed explorers are left alone; standing ones are preferred.
	local now = 10
	d = CreatureBrain.step(c, perception(now, { p1 = target(2, { condition = "Downed" }), p2 = target(20) }), regular)
	check(c.targetKey == "p2", "after recovery it switches from a downed explorer to a standing one")
	d = CreatureBrain.step(c, perception(now + 0.2, { p1 = target(2, { condition = "Downed" }) }), regular)
	check(c.state == "Return" and d.move == "Home", "with only a downed explorer nearby it returns to its den")

	-- Return ignores targets until home, then resets.
	d = CreatureBrain.step(c, perception(now + 0.4, { p2 = target(5) }, { distanceFromHome = 20 }), regular)
	check(c.state == "Return" and d.move == "Home", "a returning creature ignores targets until home")
	d = CreatureBrain.step(c, perception(now + 0.6, {}, { distanceFromHome = 1 }), regular)
	check(c.state == "Idle" and d.reset == true, "reaching the den resets the encounter")

	-- Leash, protected zones, lost sight, path failures.
	local c2 = CreatureBrain.new(0)
	CreatureBrain.step(c2, perception(0, { p1 = target(20) }), regular)
	d = CreatureBrain.step(c2, perception(0.2, { p1 = target(20) }, { distanceFromHome = regular.leashRadius + 1 }), regular)
	check(c2.state == "Return", "leaving the leash makes it return")
	local c3 = CreatureBrain.new(0)
	CreatureBrain.step(c3, perception(0, { p1 = target(20) }), regular)
	d = CreatureBrain.step(c3, perception(0.2, { p1 = target(20, { protected = true }) }), regular)
	check(c3.state == "Return", "a target inside a protected zone is dropped")
	local c4 = CreatureBrain.new(0)
	CreatureBrain.step(c4, perception(0, { p1 = target(20) }), regular)
	CreatureBrain.step(c4, perception(1, { p1 = target(20, { visible = false, noticeable = false }) }), regular)
	check(c4.state == "Pursue", "a short loss of sight keeps the chase")
	CreatureBrain.step(c4, perception(1 + regular.loseSightSeconds + 0.1, { p1 = target(20, { visible = false, noticeable = false }) }), regular)
	check(c4.state == "Return", "explorers can break contact by staying out of sight")
	local c5 = CreatureBrain.new(0)
	CreatureBrain.step(c5, perception(0, { p1 = target(20) }), regular)
	CreatureBrain.step(c5, perception(0.2, { p1 = target(20) }, { pathFailures = Config.Creatures.MaxPathFailures, maxPathFailures = Config.Creatures.MaxPathFailures }), regular)
	check(c5.state == "Return", "an unreachable target is given up after repeated path failures")
	local c7 = CreatureBrain.new(0)
	CreatureBrain.step(c7, perception(0, { p1 = target(10) }), regular)
	CreatureBrain.step(c7, perception(0.2, { p1 = target(10), p2 = target(25) }, { pathFailures = 3, maxPathFailures = 3 }), regular)
	check(c7.state == "Pursue" and c7.targetKey == "p2", "after giving up an unreachable target it can chase a reachable one")
	local c6 = CreatureBrain.new(0)
	CreatureBrain.step(c6, perception(0, { p1 = target(20) }), regular)
	CreatureBrain.step(c6, perception(0.2, { p1 = target(20) }, { selfProtected = true }), regular)
	check(c6.state == "Return", "a creature pushed into a protected zone leaves it")
	check(CreatureBrain.kill(c6) == true and CreatureBrain.kill(c6) == false, "death happens once")
	check(CreatureBrain.step(c6, perception(5, { p1 = target(1) }), regular).move == "Stop", "a dead creature does nothing")

	-- Encounters: locked until defeated, exactly one reward, stale cycles ignored.
	local e = EncounterCore.new("den")
	local cycle = EncounterCore.beginCycle(e, 0)
	check(EncounterCore.isLocked(e), "the cache starts locked")
	local made = 0
	local function makeReward()
		made += 1
		return `reward-{made}`
	end
	local ok, rewardId = EncounterCore.guardianDefeated(e, cycle, makeReward)
	check(ok and rewardId == "reward-1" and not EncounterCore.isLocked(e), "defeat unlocks the cache with one reward")
	check(EncounterCore.guardianDefeated(e, cycle, makeReward) == false and made == 1, "a repeated death callback creates no second reward")
	check(EncounterCore.guardianDefeated(e, cycle - 1, makeReward) == false and made == 1, "a stale cycle creates nothing")
	check(EncounterCore.rewardClaimed(e, "someone-else", 1, 60) == false, "claiming another relic does not end the cycle")
	check(not EncounterCore.resetDue(e, 1000), "an unclaimed reward keeps the encounter open (players leaving never resets it)")
	check(EncounterCore.rewardClaimed(e, "reward-1", 10, 60) == true, "claiming the reward starts the cooldown")
	check(EncounterCore.rewardClaimed(e, "reward-1", 11, 60) == false, "a repeated claim callback does nothing")
	check(not EncounterCore.resetDue(e, 69) and EncounterCore.resetDue(e, 70), "the encounter resets after the configured time")
	local cycle2 = EncounterCore.beginCycle(e, 70)
	check(cycle2 == cycle + 1 and EncounterCore.isLocked(e) and e.rewardId == nil, "the next cycle is locked again with no reward yet")
	check(EncounterCore.guardianDefeated(e, cycle, makeReward) == false, "the old cycle's guardian cannot unlock the new cycle")
	check(EncounterCore.guardianLost(e, cycle2, 80, 30) == true and EncounterCore.guardianDefeated(e, cycle2, makeReward) == false and made == 1, "a guardian lost to the environment gives no reward")
	for i = 1, 20 do
		local cyc = EncounterCore.beginCycle(e, 200 + i)
		EncounterCore.guardianDefeated(e, cyc, makeReward)
		EncounterCore.rewardClaimed(e, `reward-{made}`, 200 + i, 0)
	end
	check(made == 21 and e.cycle == cycle2 + 20, "repeated encounters create exactly one reward per cycle")
	-- The reward is a normal specimen: contested pickup has one winner, and its identity holds.
	local store = RelicStore.new(function()
		return 0
	end)
	local rng = Random.new(99)
	local counter = 0
	local e2 = EncounterCore.new("contest")
	local c2cycle = EncounterCore.beginCycle(e2, 0)
	local rewardSpecimen
	EncounterCore.guardianDefeated(e2, c2cycle, function()
		local pick = EncounterCore.pickReward(Config.Encounters.RewardTable, rng:NextNumber())
		rewardSpecimen = SpecimenFactory.create(pick.typeId, pick.qualityMin, pick.qualityMax, rng, function()
			counter += 1
			return `cache-reward-{counter}`
		end)
		store:add(rewardSpecimen)
		return rewardSpecimen.id
	end)
	local identity = RelicStore.fingerprint(rewardSpecimen)
	local first = store:claim(rewardSpecimen.id, 101)
	local second, secondReason = store:claim(rewardSpecimen.id, 102)
	check(first == true and second == false and secondReason == "AlreadyOwned", "contested cache pickup: exactly one winner")
	check(EncounterCore.rewardClaimed(e2, rewardSpecimen.id, 1, 60) and counter == 1, "one reward specimen per cycle")
	store:processDeath(101, 0, 0)
	check(store:claim(rewardSpecimen.id, 102) == true and RelicStore.fingerprint(rewardSpecimen) == identity, "the reward keeps its ID and traits through death and recovery")
	store:registerCarried(102)
	check(rewardSpecimen.registered and RelicStore.fingerprint(rewardSpecimen) == identity, "the reward keeps its ID and traits through registration")

	local pickA = EncounterCore.pickReward(Config.Encounters.RewardTable, 0)
	local pickB = EncounterCore.pickReward(Config.Encounters.RewardTable, 0.999)
	check(pickA.typeId ~= nil and pickB.typeId ~= nil and Config.RelicTypes[pickA.typeId] and Config.RelicTypes[pickB.typeId], "reward picks are real relic types")

	-- Melee hit selection.
	local weapon = Config.Items.StarterBlade
	local origin, look = v3(0, 0, 0), v3(0, 0, -1)
	local candidates = {
		{ id = "front", position = v3(0, 0, -5), radius = 1, visible = true },
		{ id = "front", position = v3(0, 0, -5), radius = 1, visible = true }, -- duplicate entry
		{ id = "behind", position = v3(0, 0, 5), radius = 1, visible = true },
		{ id = "far", position = v3(0, 0, -30), radius = 1, visible = true },
		{ id = "walled", position = v3(1, 0, -4), radius = 1, visible = false },
		{ id = "nan", position = v3(0 / 0, 0, -3), radius = 1, visible = true },
		{ id = "hugging", position = v3(0, 0, 0.5), radius = 1.5, visible = true },
	}
	local hits = MeleeRules.selectHits(origin, look, candidates, weapon, Config.Combat.RangeTolerance)
	local set = {}
	for _, id in hits do
		set[id] = (set[id] or 0) + 1
	end
	check(set.front == 1, "a target in front and in range is hit exactly once per swing")
	check(not set.behind and not set.far and not set.walled and not set.nan, "behind, out of range, blocked, and non-finite targets are not hit")
	check(set.hugging == 1, "a target overlapping the attacker counts as in front")
	check(#MeleeRules.selectHits(v3(0 / 0, 0, 0), look, candidates, weapon, 1) == 0, "a non-finite attacker position hits nothing")
	check(#MeleeRules.selectHits(origin, v3(0, 1, 0), candidates, weapon, 1) == 0, "a facing with no horizontal direction hits nothing")
	local swing = { lastSwingAt = 10 }
	check(select(2, MeleeRules.canSwing(swing, 10 + weapon.cooldown / 2, weapon)) == "Cooldown", "attack spam is refused by the cooldown")
	check(MeleeRules.canSwing(swing, 10 + weapon.cooldown, weapon) == true, "the next swing is allowed after the cooldown")

	return t
end
