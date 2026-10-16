--[[
	Milestone 4 survival rules: damage and downing, revive and self-rescue tokens,
	bleedout, expedition runs, timed actions, rescue exclusivity, ordinary items and drops.
	Pure modules only; fake clock.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local BusyCore = require(Server.BusyCore)
local ExpeditionCore = require(Server.ExpeditionCore)
local GearStore = require(Server.GearStore)
local RescueCore = require(Server.RescueCore)
local VitalsCore = require(Server.VitalsCore)
local TestKit = require(script.Parent.TestKit)

local DOWN_CFG = { healthWhileDowned = 1, bleedoutSeconds = 30 }

return function()
	local t = TestKit.suite("Survival")
	local check = t.check

	-- Damage through the central interface downs instead of killing.
	local v = VitalsCore.new(1, 100)
	check(VitalsCore.damage(v, 40, 0, DOWN_CFG) == "Hurt" and v.health == 60, "damage reduces health")
	for _, bad in { 0, -5, 0 / 0, math.huge, "10", nil } do
		check(VitalsCore.damage(v, bad, 0, DOWN_CFG) == "Refused", `bad damage amount {tostring(bad)} is refused`)
	end
	check(v.health == 60, "refused damage changes nothing")
	check(VitalsCore.damage(v, 500, 1, DOWN_CFG) == "Downed", "lethal damage downs the character")
	check(v.condition == "Downed" and v.health == 1 and v.bleedoutAt == 31 and v.downToken == 1, "downed state, health, bleedout deadline, token")
	check(VitalsCore.damage(v, 10, 2, DOWN_CFG) == "Refused", "a downed character takes no further damage")
	check(VitalsCore.heal(v, 50) == 0, "a downed character cannot heal normally")

	-- Revive: token must match; only once.
	check(select(2, VitalsCore.revive(v, 1, 0, 35)) == "StaleToken", "a stale revive token is refused")
	check(select(2, VitalsCore.revive(v, 99, 1, 35)) == "StaleCharacter", "a revive meant for another character is refused")
	check(VitalsCore.revive(v, 1, 1, 35) == true and v.condition == "Alive" and v.health == 35, "revive restores the configured health")
	check(select(2, VitalsCore.revive(v, 1, 1, 35)) == "NotDowned", "a second revive for the same down is refused")
	check(not VitalsCore.bleedoutDue(v, 1, 100), "a revived character cannot bleed out from the old down")
	VitalsCore.damage(v, 100, 50, DOWN_CFG)
	check(v.downToken == 2 and not VitalsCore.bleedoutDue(v, 1, 1000), "an old down's bleedout never fires on a new down")
	check(not VitalsCore.bleedoutDue(v, 2, 79) and VitalsCore.bleedoutDue(v, 2, 80), "bleedout fires at the deadline")
	check(VitalsCore.markDead(v) == true and VitalsCore.markDead(v) == false, "death is recorded once")
	check(select(2, VitalsCore.revive(v, 1, 2, 35)) == "NotDowned", "a dead character cannot be revived")
	-- Respawn: the new character's first down has token 1 again; the old one's revive must not apply.
	local respawned = VitalsCore.new(2, 100)
	VitalsCore.damage(respawned, 200, 0, DOWN_CFG)
	check(respawned.downToken == 1 and select(2, VitalsCore.revive(respawned, 1, 1, 35)) == "StaleCharacter", "a stale revive from the previous character does nothing after respawn")
	check(VitalsCore.heal(VitalsCore.new(2, 100), 10) == 0, "healing at full health heals nothing")

	-- Expedition runs.
	local counter = 0
	local function makeRunId()
		counter += 1
		return counter
	end
	local e = ExpeditionCore.new()
	ExpeditionCore.onZone(e, "Town", 0, makeRunId)
	check(e.phase == "Town" and e.run == nil, "a player in town has no run")
	local events = ExpeditionCore.onZone(e, "Depths", 1, makeRunId)
	check(events[1].kind == "RunStarted" and e.phase == "Exploring", "leaving town starts a run")
	local runId = e.run.id
	ExpeditionCore.onZone(e, "Camp", 2, makeRunId)
	check(e.phase == "AtCamp" and e.run.id == runId, "a camp keeps the same run")
	ExpeditionCore.onZone(e, "Depths", 3, makeRunId)
	check(e.run.id == runId, "leaving a camp does not start a new run")
	check(ExpeditionCore.useSelfRescue(e, runId, 1) == true, "the first self-rescue is allowed")
	check(ExpeditionCore.useSelfRescue(e, runId, 1) == false, "the per-run limit holds")
	ExpeditionCore.onZone(e, "Camp", 4, makeRunId)
	check(ExpeditionCore.selfRescuesLeft(e, 1) == 0, "visiting a camp does not reset the allowance")
	events = ExpeditionCore.onZone(e, "Town", 5, makeRunId)
	check(events[1].kind == "RunFinished" and events[1].runId == runId and e.run == nil, "returning to town finishes the run once")
	check(#ExpeditionCore.onZone(e, "Town", 6, makeRunId) == 0, "staying in town finishes nothing more")
	ExpeditionCore.onZone(e, "Depths", 7, makeRunId)
	check(e.run.id ~= runId and ExpeditionCore.selfRescuesLeft(e, 1) == 1, "a new departure starts a new run with a fresh allowance")
	check(ExpeditionCore.useSelfRescue(e, runId, 1) == false, "a stale run id cannot spend the new run's allowance")
	local finished = ExpeditionCore.finish(e)
	check(finished ~= nil and ExpeditionCore.finish(e) == nil, "final death finishes the run exactly once")

	-- Timed actions.
	local b = BusyCore.new()
	local log = {}
	local valid = true
	local token = BusyCore.begin(b, "p1", {
		kind = "Heal",
		duration = 2,
		interruptible = true,
		validate = function()
			return valid, "Invalid"
		end,
		complete = function()
			table.insert(log, "done")
		end,
		cancelled = function(reason)
			table.insert(log, "cancel:" .. reason)
		end,
	}, 0)
	check(token ~= nil and select(2, BusyCore.begin(b, "p1", { kind = "Other", duration = 1, complete = function() end }, 0)) == "Busy", "one action at a time")
	BusyCore.step(b, 1)
	check(#log == 0, "nothing completes early")
	BusyCore.step(b, 2.01)
	check(log[1] == "done" and BusyCore.kind(b, "p1") == nil, "completes on the server clock")
	BusyCore.step(b, 3)
	check(#log == 1, "completes exactly once")
	BusyCore.begin(b, "p1", { kind = "Heal", duration = 2, interruptible = true, complete = function()
		table.insert(log, "done2")
	end, cancelled = function(reason)
		table.insert(log, "cancel:" .. reason)
	end }, 10)
	check(BusyCore.interrupt(b, "p1", "Damaged") and log[2] == "cancel:Damaged", "damage interrupts an interruptible action")
	BusyCore.step(b, 20)
	check(#log == 2, "an interrupted action never completes")
	valid = true
	BusyCore.begin(b, "p2", { kind = "Revive", duration = 4, interruptible = false, validate = function()
		return valid, "TooFar"
	end, complete = function()
		table.insert(log, "revived")
	end, cancelled = function(reason)
		table.insert(log, "cancel:" .. reason)
	end }, 0)
	check(not BusyCore.interrupt(b, "p2", "Damaged"), "non-interruptible actions ignore interrupt")
	valid = false
	BusyCore.step(b, 1)
	check(log[3] == "cancel:TooFar" and BusyCore.kind(b, "p2") == nil, "an action stops when its conditions fail")

	-- Bandage flow: consumed only on completion, never when interrupted.
	local bandageGear = GearStore.new(Config.Items, Config.ItemOrder)
	bandageGear:refill(3)
	local before = bandageGear:count(3, "Bandage")
	local bb = BusyCore.new()
	local function bandageSpec()
		return {
			kind = "Bandage",
			duration = Config.Items.Bandage.useTime,
			interruptible = true,
			complete = function()
				bandageGear:consume(3, "Bandage", 1)
			end,
		}
	end
	BusyCore.begin(bb, "p3", bandageSpec(), 0)
	BusyCore.interrupt(bb, "p3", "Damaged")
	BusyCore.step(bb, 100)
	check(bandageGear:count(3, "Bandage") == before, "an interrupted bandage is not consumed")
	BusyCore.begin(bb, "p3", bandageSpec(), 200)
	BusyCore.step(bb, 200 + Config.Items.Bandage.useTime)
	BusyCore.step(bb, 300)
	check(bandageGear:count(3, "Bandage") == before - 1, "a completed bandage is consumed exactly once")

	-- Rescue exclusivity.
	local r = RescueCore.new()
	check(RescueCore.claim(r, "down", "helperA", 1) == true, "a helper can start a revive")
	check(select(2, RescueCore.claim(r, "down", "helperB", 1)) == "AlreadyBeingRevived", "a second helper is refused")
	check(select(2, RescueCore.claim(r, "other", "helperA", 1)) == "HelperBusy", "a helper revives one player at a time")
	check(select(2, RescueCore.claim(r, "self", "self", 1)) == "SelfRevive", "a player cannot revive themselves this way")
	RescueCore.releaseHelper(r, "helperA")
	check(RescueCore.claim(r, "down", "helperB", 1) == true, "after cancelling, another helper can start")

	-- Ordinary items and drops.
	local gear = GearStore.new(Config.Items, Config.ItemOrder)
	local added = gear:refill(7)
	check(gear:count(7, "Bandage") == Config.Items.Bandage.townRefill and added.StarterBlade == 1, "town refill gives the basic loadout")
	gear:refill(7)
	gear:refill(7)
	check(gear:count(7, "Bandage") == Config.Items.Bandage.townRefill and gear:count(7, "StarterBlade") == 1, "repeated refills never exceed the refill amount")
	check(gear:add(7, "Bandage", 100) == Config.Items.Bandage.maxCarry - Config.Items.Bandage.townRefill, "carrying is capped")
	check(gear:count(7, "Bandage") == Config.Items.Bandage.maxCarry, "count stops at capacity")
	gear:refill(7)
	check(gear:count(7, "Bandage") == Config.Items.Bandage.maxCarry, "refill keeps extra picked-up items")
	check(gear:consume(7, "Bandage", 1) == true and gear:count(7, "Bandage") == Config.Items.Bandage.maxCarry - 1, "using a bandage consumes exactly one")
	check(gear:consume(7, "RescueKit", 5) == false, "cannot consume more than carried")
	check(gear:weapon(7) == "StarterBlade", "the starter blade counts as the equipped weapon")

	local carried = gear:takeAll(7)
	local dropId = gear:createDrop(carried)
	check(dropId ~= nil and gear:weapon(7) == nil and gear:count(7, "Bandage") == 0, "final death moves everything into a drop")
	local secondDrop = gear:createDrop({ Bandage = 1 })
	check(secondDrop ~= dropId, "drop ids are unique")
	local taken = gear:claimDrop(dropId, 8)
	check(taken and taken.Bandage == Config.Items.Bandage.maxCarry - 1 and taken.StarterBlade == 1, "the first claimer gets the authoritative quantities")
	check(select(2, gear:claimDrop(dropId, 9)) == "Gone", "a competing claim gets nothing")
	check(select(2, gear:claimDrop(dropId, 8)) == "Gone", "claiming the same drop twice cannot duplicate items")
	gear:add(10, "Bandage", Config.Items.Bandage.maxCarry)
	local partialDrop = gear:createDrop({ Bandage = 2, RescueKit = 1 })
	local partial, emptied = gear:claimDrop(partialDrop, 10)
	check(partial and partial.RescueKit == 1 and partial.Bandage == nil and emptied == false, "only what fits is taken")
	check(gear:dropContents(partialDrop).Bandage == 2, "the rest stays in the same drop")
	check(select(2, gear:claimDrop(partialDrop, 10)) == "NoRoom", "a full player cannot take more")
	check(gear:createDrop({}) == nil and gear:createDrop({ Unknown = 3 }) == nil, "empty or unknown drops are not created")

	return t
end
