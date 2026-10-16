--[[
	Basic melee (milestone 4). Server only.

	The client only asks to attack ("Attack" with no arguments). The server:
	  - requires a loaded session, a standing character (not Downed), a carried weapon, no
	    timed action in progress (bandage, revive, self-rescue), the weapon cooldown to
	    have passed, and the attacker outside protected zones (no farming from camp);
	  - plays a simple visible swing (the welded blade tilts back, then sweeps forward
	    with a trail), then resolves the hit after the weapon's windup;
	  - on resolution re-checks the same character, condition, and zone, then picks
	    targets from its own positions with MeleeRules: range, arc in front of the
	    attacker's facing, line of sight with no world geometry in between, each creature
	    at most once per swing. Damage comes from the weapon definition only.
	Player-to-player damage stays off (Config.Combat.PlayerVsPlayer = false): only
	creatures are candidates. No parry or combo system yet.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Busy = require(script.Parent.Busy)
local Characters = require(script.Parent.Characters)
local Poses = require(script.Parent.Poses)
local Creatures = require(script.Parent.Creatures)
local Gear = require(script.Parent.Gear)
local Guard = require(script.Parent.Guard)
local MeleeRules = require(script.Parent.MeleeRules)
local ServerNet = require(script.Parent.ServerNet)
local Vitals = require(script.Parent.Vitals)
local Zones = require(script.Parent.Zones)

local Combat = {}

local swings: { [Player]: { lastSwingAt: number?, swingId: number } } = {}

local function swingVisual(player: Player, windup: number)
	local visual = Gear.weaponVisual(player)
	if not visual or not visual.weld.Parent then
		return
	end
	local weld, base = visual.weld, visual.baseC0
	local back = base * CFrame.Angles(math.rad(70), math.rad(-30), 0)
	local through = base * CFrame.Angles(math.rad(-60), math.rad(40), 0)
	TweenService:Create(weld, TweenInfo.new(windup), { C0 = back }):Play()
	task.delay(windup, function()
		if not weld.Parent then
			return
		end
		visual.trail.Enabled = true
		local sweep = TweenService:Create(weld, TweenInfo.new(0.12), { C0 = through })
		sweep:Play()
		sweep.Completed:Wait()
		visual.trail.Enabled = false
		if weld.Parent then
			TweenService:Create(weld, TweenInfo.new(0.25), { C0 = base }):Play()
		end
	end)
end

local function obstructed(fromPos: Vector3, toPos: Vector3, attacker: Model, targetModel: Model): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { attacker, targetModel }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	return workspace:Raycast(fromPos, toPos - fromPos, params) ~= nil
end

local function resolve(player: Player, charId: number, swingId: number, weaponId: string)
	local swing = swings[player]
	if not swing or swing.swingId ~= swingId or Vitals.charId(player) ~= charId or Vitals.condition(player) ~= "Alive" then
		return
	end
	local root = Characters.liveRoot(player)
	local character = player.Character
	if not root or not character or Zones.isProtected(root.Position) then
		return
	end
	local weapon = Config.Items[weaponId]
	local candidates = {}
	for _, creature in Creatures.living() do
		local position = creature.root.Position
		if not Zones.isProtected(position) then
			table.insert(candidates, {
				id = creature.id,
				position = position,
				radius = creature.radius,
				visible = not obstructed(root.Position, position, character, creature.model),
			})
		end
	end
	local hits = MeleeRules.selectHits(root.Position, root.CFrame.LookVector, candidates, weapon, Config.Combat.RangeTolerance)
	for _, creatureId in hits do
		local dealt = Creatures.damage(creatureId, weapon.damage, player)
		if dealt then
			ServerNet.combatFx(player, { kind = "Hit", position = dealt.position, amount = weapon.damage, killed = dealt.killed })
		end
	end
end

-- Returns (ok, message). The message is empty for a normal swing.
function Combat.requestAttack(player: Player): (boolean, string)
	local allowed, blocked = Guard.checkActive(player)
	if not allowed then
		return false, blocked :: string
	end
	local weaponId, weapon = Gear.weapon(player)
	if not weaponId then
		return false, "You have no weapon. Take basic supplies in town."
	end
	if Busy.kind(player) then
		return false, "Finish or cancel what you are doing first."
	end
	local root = Characters.liveRoot(player)
	if not root then
		return false, "You cannot attack right now."
	end
	if Zones.isProtected(root.Position) then
		return false, "You cannot attack from inside town or a camp."
	end
	local swing = swings[player] or { swingId = 0 }
	swings[player] = swing
	local now = os.clock()
	local ok = MeleeRules.canSwing(swing, now, weapon)
	if not ok then
		return false, "" -- still on cooldown; spam is simply ignored
	end
	swing.lastSwingAt = now
	swing.swingId += 1
	local swingId, charId = swing.swingId, Vitals.charId(player) :: number
	swingVisual(player, weapon.windup)
	Poses.swing(player, weapon.windup)
	task.delay(weapon.windup, resolve, player, charId, swingId, weaponId)
	return true, ""
end

function Combat.start()
	Players.PlayerRemoving:Connect(function(player)
		swings[player] = nil
	end)
end

return Combat
