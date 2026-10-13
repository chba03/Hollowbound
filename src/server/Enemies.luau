--[[
	The Hollow's creatures (Config.Enemies). Server side.

	Each layer keeps PerLayer creatures of its kind alive on its ledges. A creature:
	  - wanders near where it spawned;
	  - chases the nearest player on its ledge within AggroRadius (not players in a camp,
	    on a rope, or dead), and gives up past LeashRadius from its spawn;
	  - attacks within AttackRange every attackCooldown (a quick lunge);
	  - stays on the ledge (between the ledge's inner edge and the wall), so it can never
	    reach the rope line, and never enters a camp's ring (camps are refuges);
	  - dies to pickaxes (server Arsenal tags hits with LastHitBy); the last hitter gets
	    its reward, and a new one spawns elsewhere after RespawnSeconds.

	Movement is kinematic (anchored models moved with PivotTo, standing on the terrain
	via Ground.below), cheap and predictable, and only runs for creatures within
	SimRadius of some player.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))
local Characters = require(script.Parent.Characters)
local EnemyModels = require(script.Parent.EnemyModels)
local Ground = require(script.Parent.Ground)
local Hollow = require(script.Parent.Hollow)
local PlayerData = require(script.Parent.PlayerData)
local ServerNet = require(script.Parent.ServerNet)

local Enemies = {}

type Enemy = {
	kind: any,
	model: Model,
	humanoid: Humanoid,
	home: Vector3, -- spawn point on the ground
	ledgeY: number, -- planned ledge height (for ground lookups)
	position: Vector3, -- current ground point
	facing: Vector3,
	wanderTarget: Vector3,
	nextWander: number,
	lastAttack: number,
	groundY: number,
	groundAt: number,
	phase: number,
	dead: boolean,
}

local enemies: { Enemy } = {}
local folder: Folder
local rng = Random.new()
local center: Vector3

local function cfg()
	return Config.Enemies
end

-- The ledge band at a depth: (inner radius, outer radius) that keeps creatures on the
-- ledge and clear of the rope line.
local function band(depth: number): (number, number)
	return Config.Hollow.LedgeInnerRadius + 4, Progression.pitRadiusAt(depth) - 3
end

local function clampToLedge(position: Vector3, depth: number): Vector3
	local inner, outer = band(depth)
	local flat = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	local radius = flat.Magnitude
	if radius < 0.01 then
		return position
	end
	local r = math.clamp(radius, inner, outer)
	return Vector3.new(center.X, position.Y, center.Z) + flat.Unit * r
end

local function inCamp(position: Vector3): boolean
	for _, zone in CollectionService:GetTagged(Config.Tags.CampZone) do
		if zone:IsA("BasePart") then
			local radius = zone:GetAttribute("Radius")
			local reach = (if typeof(radius) == "number" then radius else zone.Size.X / 2) + 3
			local offset = position - zone.Position
			if Vector2.new(offset.X, offset.Z).Magnitude <= reach and math.abs(offset.Y) <= zone.Size.Y then
				return true
			end
		end
	end
	return false
end

-- A random ground point on one of the layer's ledges, outside camps.
local function spawnPoint(layer: number): (Vector3?, number)
	local H = Config.Hollow
	for _ = 1, 20 do
		local depth = (layer - 1) * H.LayerHeight + H.LedgeDepths[rng:NextInteger(1, #H.LedgeDepths)]
		local inner, outer = band(depth)
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(inner, outer)
		local nominal = Vector3.new(center.X + math.cos(angle) * radius, center.Y - depth, center.Z + math.sin(angle) * radius)
		local groundY = Ground.below(nominal)
		if groundY and not inCamp(nominal) then
			return Vector3.new(nominal.X, groundY, nominal.Z), nominal.Y
		end
	end
	return nil, 0
end

local function place(enemy: Enemy, lift: number)
	enemy.model:PivotTo(CFrame.lookAt(enemy.position + Vector3.new(0, lift, 0), enemy.position + Vector3.new(0, lift, 0) + enemy.facing))
end

local function spawn(kind)
	local point, ledgeY = spawnPoint(kind.layer)
	if not point then
		return
	end
	local model = EnemyModels.build(kind)
	model:SetAttribute("Layer", kind.layer)
	CollectionService:AddTag(model, Config.Tags.Enemy)
	local angle = rng:NextNumber(0, 2 * math.pi)
	local enemy: Enemy = {
		kind = kind,
		model = model,
		humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid,
		home = point,
		ledgeY = ledgeY,
		position = point,
		facing = Vector3.new(math.cos(angle), 0, math.sin(angle)),
		wanderTarget = point,
		nextWander = 0,
		lastAttack = 0,
		groundY = point.Y,
		groundAt = 0,
		phase = rng:NextNumber(0, 10),
		dead = false,
	}
	place(enemy, 0)
	model.Parent = folder
	table.insert(enemies, enemy)

	enemy.humanoid.Died:Connect(function()
		if enemy.dead then
			return
		end
		enemy.dead = true
		local killerId = model:GetAttribute("LastHitBy")
		local killer = if typeof(killerId) == "number" then Players:GetPlayerByUserId(killerId) else nil
		if killer then
			local reward = math.floor(60 * Config.Layers[kind.layer].incomeMultiplier)
			PlayerData.addCash(killer, reward)
			PlayerData.publish(killer)
			ServerNet.notify(killer, `Defeated a {kind.name}: +{Progression.formatCash(reward)}`, "success")
		end
		-- Sink and fade, then respawn elsewhere.
		task.spawn(function()
			for i = 1, 10 do
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
						part.Transparency = math.min(1, part.Transparency + 0.1)
					end
				end
				place(enemy, -i * 0.15)
				task.wait(0.05)
			end
			model:Destroy()
			local index = table.find(enemies, enemy)
			if index then
				table.remove(enemies, index)
			end
			task.wait(cfg().RespawnSeconds)
			spawn(kind)
		end)
	end)
end

-- The nearest player this creature can go after, or nil.
local function quarry(enemy: Enemy): (Player?, BasePart?)
	local c = cfg()
	local best, bestRoot, bestDistance = nil, nil, c.AggroRadius
	for _, player in Players:GetPlayers() do
		local root = Characters.liveRoot(player)
		if not root or player:GetAttribute("HB_OnRope") or player:GetAttribute("HB_Zone") == "Camp" then
			continue
		end
		local offset = root.Position - enemy.position
		if math.abs(offset.Y) > c.AggroHeight then
			continue
		end
		local distance = Vector2.new(offset.X, offset.Z).Magnitude
		if distance < bestDistance and (root.Position - enemy.home).Magnitude < c.LeashRadius then
			best, bestRoot, bestDistance = player, root, distance
		end
	end
	return best, bestRoot
end

local function nearAnyPlayer(position: Vector3, radius: number): boolean
	for _, player in Players:GetPlayers() do
		local root = Characters.liveRoot(player)
		if root and (root.Position - position).Magnitude <= radius then
			return true
		end
	end
	return false
end

local function step(enemy: Enemy, dt: number, now: number)
	local c = cfg()
	local kind = enemy.kind
	if not nearAnyPlayer(enemy.position, c.SimRadius) then
		return
	end
	local depth = center.Y - enemy.ledgeY
	local player, target = quarry(enemy)
	local goal: Vector3
	local speed = kind.speed
	if target then
		goal = target.Position
	else
		if now >= enemy.nextWander then
			local wander = enemy.home + Vector3.new(rng:NextNumber(-18, 18), 0, rng:NextNumber(-18, 18))
			enemy.wanderTarget = clampToLedge(wander, depth)
			enemy.nextWander = now + rng:NextNumber(3, 7)
		end
		goal = enemy.wanderTarget
		speed *= 0.35
	end

	local flat = Vector3.new(goal.X - enemy.position.X, 0, goal.Z - enemy.position.Z)
	local distance = flat.Magnitude
	local stopAt = if target then c.AttackRange * 0.8 else 1
	local lunge = 0
	if distance > stopAt then
		local move = flat.Unit * math.min(speed * dt, distance - stopAt)
		local nextPosition = clampToLedge(enemy.position + move, depth)
		if not inCamp(nextPosition) then
			enemy.position = Vector3.new(nextPosition.X, enemy.position.Y, nextPosition.Z)
		end
		enemy.facing = flat.Unit
	elseif target then
		enemy.facing = flat.Unit
	end

	-- Stand on the ground (looked up a few times a second).
	if now - enemy.groundAt > 0.25 then
		enemy.groundAt = now
		local groundY = Ground.below(Vector3.new(enemy.position.X, enemy.ledgeY, enemy.position.Z))
		if groundY then
			enemy.groundY = groundY
		end
	end
	enemy.position = Vector3.new(enemy.position.X, enemy.groundY, enemy.position.Z)

	-- Attack.
	if player and target and distance <= c.AttackRange and now - enemy.lastAttack >= kind.attackCooldown then
		enemy.lastAttack = now
		local humanoid = target.Parent and target.Parent:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:TakeDamage(kind.damage)
		end
	end
	if now - enemy.lastAttack < 0.25 then
		lunge = 1.2 * math.sin((now - enemy.lastAttack) / 0.25 * math.pi)
	end

	-- Body motion: hoppers hop, wraiths and seraphs float and bob, others sway slightly.
	enemy.phase += dt * (if distance > stopAt then speed * 0.6 else 1.5)
	local lift = 0
	if kind.shape == "hopper" then
		lift = math.abs(math.sin(enemy.phase)) * 1.2
	elseif kind.shape == "wraith" or kind.shape == "seraph" then
		lift = 1.5 + math.sin(enemy.phase * 0.5) * 0.5
	else
		lift = math.abs(math.sin(enemy.phase)) * 0.15
	end
	local at = enemy.position + enemy.facing * lunge + Vector3.new(0, lift, 0)
	enemy.model:PivotTo(CFrame.lookAt(at, at + enemy.facing))
end

function Enemies.start()
	local hollowCenter = Hollow.center()
	if not hollowCenter then
		warn("[Hollowbound] No Hollow: creatures disabled")
		return
	end
	center = hollowCenter
	folder = Instance.new("Folder")
	folder.Name = "HollowboundCreatures"
	folder.Parent = workspace

	for _, kind in Config.Enemies.Kinds do
		for _ = 1, Config.Enemies.PerLayer do
			spawn(kind)
		end
	end
	print(`[Hollowbound] Creatures: {#enemies} across {#Config.Enemies.Kinds} layers`)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		local interval = 1 / Config.Enemies.TickRate
		if accumulated < interval then
			return
		end
		local elapsed = accumulated
		accumulated = 0
		local now = os.clock()
		for _, enemy in table.clone(enemies) do
			if not enemy.dead then
				step(enemy, elapsed, now)
			end
		end
	end)
end

return Enemies
