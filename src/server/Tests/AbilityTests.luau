--[[
	Ability rules: activation, service, and charge gates; cooldowns that survive swaps,
	copies, and death; trait-based tuning within caps. Uses a fake clock; no world effects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local LoadoutRules = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("LoadoutRules"))
local AbilityRules = require(Server.AbilityRules)
local RelicStore = require(Server.RelicStore)
local SpecimenFactory = require(Server.SpecimenFactory)
local TestKit = require(script.Parent.TestKit)

local function cooldownTable()
	local deadlines = {}
	return {
		getDeadline = function(abilityId)
			return deadlines[abilityId]
		end,
		setDeadline = function(abilityId, deadline)
			deadlines[abilityId] = deadline
		end,
		deadlines = deadlines,
	}
end

return function()
	local t = TestKit.suite("Abilities")
	local check = t.check
	local makeId = TestKit.idMaker("ability")
	local rng = Random.new(777)
	local store = RelicStore.new(function()
		return 0
	end)
	local rules = LoadoutRules.forStore()
	local u = 30
	local cooldowns = cooldownTable()
	local now = 1000

	local hook = SpecimenFactory.create("Windhook", 0.10, 0.20, rng, makeId) -- Common, needs activation
	local lensA = SpecimenFactory.create("EchoLens", 0.95, 0.99, rng, makeId) -- Exceptional
	local lensB = SpecimenFactory.create("EchoLens", 0.40, 0.60, rng, makeId) -- Uncommon copy
	for _, specimen in { hook, lensA, lensB } do
		store:add(specimen)
		store:claim(specimen.id, u)
	end

	check(select(2, AbilityRules.tryUse(store, cooldowns, u, 1, now)) == "SlotEmpty", "an empty slot cannot be used")
	check(select(2, AbilityRules.tryUse(store, cooldowns, u, 9, now)) == "BadSlot", "a made-up slot cannot be used")
	check(select(2, AbilityRules.tryUse(store, cooldowns, u, "1", now)) == "BadSlot", "a non-number slot cannot be used")

	-- Windhook needs activation; appraisal is not required.
	store:equip(u, hook.id, 1, rules)
	check(select(2, AbilityRules.tryUse(store, cooldowns, u, 1, now)) == "NeedsActivation", "unactivated Windhook cannot be used")
	store:activate(u, hook.id, true)
	local ok, _, used, params = AbilityRules.tryUse(store, cooldowns, u, 1, now)
	check(ok and used == hook and hook.charges == Config.Abilities.Windhook.maxCharges - 1, "activated Windhook works unappraised and spends a charge")
	check(params.forwardSpeed <= Config.Abilities.Windhook.maxForwardSpeed and params.upwardSpeed <= Config.Abilities.Windhook.maxUpwardSpeed, "Windhook speeds stay within the server caps")
	check(params.duration == Config.Abilities.Windhook.duration, "Windhook duration is fixed by config")
	local reason, _, _, remaining = select(2, AbilityRules.tryUse(store, cooldowns, u, 1, now + 0.1))
	check(reason == "CoolingDown" and remaining and remaining > 0, "Windhook respects its cooldown")
	check(hook.charges == Config.Abilities.Windhook.maxCharges - 1, "a refused use spends no charge")

	-- Echo Lens works immediately; its cooldown is shared by every copy and survives swaps.
	store:equip(u, lensA.id, 2, rules)
	check(AbilityRules.tryUse(store, cooldowns, u, 2, now) == true, "Echo Lens works right after pickup")
	store:equip(u, lensB.id, 3, rules)
	check(select(2, AbilityRules.tryUse(store, cooldowns, u, 3, now + 1)) == "CoolingDown", "another copy cannot bypass the cooldown")
	store:unequip(u, 2, rules)
	store:equip(u, lensA.id, 2, rules)
	check(select(2, AbilityRules.tryUse(store, cooldowns, u, 2, now + 1)) == "CoolingDown", "unequipping and re-equipping does not reset the cooldown")
	local lensCooldown = cooldowns.deadlines.EchoLens - now
	check(AbilityRules.tryUse(store, cooldowns, u, 3, now + lensCooldown + 0.01) == true, "the copy works once the cooldown ends")

	-- Charges run out and only service refills them.
	local clock = now + 100
	while hook.charges > 0 do
		AbilityRules.tryUse(store, cooldowns, u, 1, clock)
		clock += 100
	end
	check(select(2, AbilityRules.tryUse(store, cooldowns, u, 1, clock)) == "NoCharges", "an empty Windhook cannot be used")
	store:registerCarried(u)
	check(hook.charges == 0, "registration does not refill charges")
	store:service(u, hook.id, 1, Config.Abilities.Windhook.maxCharges)
	check(AbilityRules.tryUse(store, cooldowns, u, 1, clock) == true, "service refills charges")

	-- Registered relics needing service stay owned but unusable; cooldowns survive death.
	local deadlineBefore = cooldowns.deadlines.Windhook
	store:processDeath(u, 0, 0)
	check(select(2, AbilityRules.tryUse(store, cooldowns, u, 1, clock + 100)) == "NeedsService", "a relic needing service cannot be used")
	check(cooldowns.deadlines.Windhook == deadlineBefore, "death does not reset cooldowns")

	-- A dropped relic cannot be used by its former owner; its new owner has their own cooldowns.
	local spare = SpecimenFactory.create("EchoLens", 0.4, 0.6, rng, makeId)
	store:add(spare)
	store:claim(spare.id, 31)
	store:equip(31, spare.id, 1, rules)
	store:processDeath(31, 0, 0)
	check(select(2, AbilityRules.tryUse(store, cooldownTable(), 31, 1, clock)) == "SlotEmpty", "the former owner cannot use a dropped relic")
	store:claim(spare.id, 32)
	check(select(2, AbilityRules.tryUse(store, cooldownTable(), 32, 1, clock)) == "SlotEmpty", "a recovered relic must be equipped first")
	store:equip(32, spare.id, 1, rules)
	check(AbilityRules.tryUse(store, cooldownTable(), 32, 1, clock) == true, "the new owner can use the recovered relic")

	-- Traits make copies differ; a missing trait uses the weakest value, never a new roll.
	local strong = SpecimenFactory.create("Windhook", 0.95, 0.99, rng, makeId)
	local weak = SpecimenFactory.create("Windhook", 0.10, 0.15, rng, makeId)
	check(AbilityRules.params(strong).forwardSpeed > AbilityRules.params(weak).forwardSpeed, "a better specimen reaches farther")
	local bare = { typeId = "Windhook", traits = {} }
	check(AbilityRules.params(bare).forwardSpeed == Config.Abilities.Windhook.forwardSpeed.worst, "a missing trait uses the weakest value")
	check(AbilityRules.params(strong).radius == nil and AbilityRules.params(lensA).radius ~= nil, "parameters match the ability")

	return t
end
