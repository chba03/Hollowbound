--[[
	Server-controlled creatures (milestone 4). One archetype; variants differ only in
	Config.Creatures.Variants. Decisions come from CreatureBrain; this module measures
	the world, moves the body, resolves strikes, and cleans up. Server only.

	Perception: line of sight is a raycast that only world geometry can block (characters
	and creatures are ignored). New targets need to be seen inside the field of view and
	detection radius, or be within hearing radius. Explorers break contact by staying out
	of sight (loseSightSeconds), leaving the leash, or entering a town or camp.

	Movement: Humanoid:MoveTo, straight when the way is clear and close, otherwise
	PathfindingService with at most one computation per RepathInterval. A failed path,
	a waypoint inside a protected zone, or no progress for StuckSeconds counts as a path
	failure; after MaxPathFailures the brain gives that target up and returns to its den.
	Creatures never step into protected zones; one pushed in leaves at once.

	Strike: after the telegraph (eyes and body turn red, a "!" shows, nearby players get
	a HUD warning) the server checks the target is still in range, in front, in sight,
	and outside protected zones, then deals damage through Vitals.damagePlayer.

	Budget: at most MaxActive creatures, one shared update loop every TickInterval;
	creatures with no explorer within DormantRadius skip perception.
]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Characters = require(script.Parent.Characters)
local CreatureBrain = require(script.Parent.CreatureBrain)
local ServerNet = require(script.Parent.ServerNet)
local Vitals = require(script.Parent.Vitals)
local Zones = require(script.Parent.Zones)

local Creatures = {}

local creatures: { [number]: any } = {}
local nextId = 0
local folder: Folder
local rng = Random.new()

local WARN_RADIUS = 80
local TELEGRAPH_COLOR = Color3.fromRGB(230, 60, 40)

local function count(): number
	local n = 0
	for _ in creatures do
		n += 1
	end
	return n
end

local function worldOnlyParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local loot = workspace:FindFirstChild("HollowboundWorldLoot")
	local relics = workspace:FindFirstChild("HollowboundWorldRelics")
	if loot then
		table.insert(exclude, loot)
	end
	if relics then
		table.insert(exclude, relics)
	end
	params.FilterDescendantsInstances = exclude
	return params
end

local function clearLine(fromPos: Vector3, toPos: Vector3, params: RaycastParams): boolean
	return workspace:Raycast(fromPos, toPos - fromPos, params) == nil
end

-- Model -------------------------------------------------------------------------------------

local function weldTo(root: BasePart, part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

local function buildModel(cfg, position: Vector3)
	local s = cfg.scale
	local model = Instance.new("Model")
	model.Name = cfg.displayName

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.4, 2, 3) * s
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model

	local hipHeight = 1.1 * s
	local rootCFrame = CFrame.new(position + Vector3.new(0, hipHeight + root.Size.Y / 2, 0))
	root.CFrame = rootCFrame

	local function part(name, size, offset, color, material, shape)
		local p = Instance.new(if shape == "Wedge" then "WedgePart" else "Part")
		p.Name = name
		p.Size = size * s
		if shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		end
		p.Color = color
		p.Material = material
		p.CFrame = rootCFrame * offset
		p.Parent = model
		weldTo(root, p)
		return p
	end
	local body = part("Body", Vector3.new(3, 1.6, 4), CFrame.new(0, 0, 0), cfg.color, Enum.Material.Slate)
	part("Head", Vector3.new(1.6, 1.3, 1.6), CFrame.new(0, 0.3 * s, -2.4 * s), cfg.color, Enum.Material.Slate)
	local eyes = {
		part("EyeL", Vector3.new(0.3, 0.3, 0.2), CFrame.new(-0.4 * s, 0.5 * s, -3.2 * s), Color3.fromRGB(255, 220, 90), Enum.Material.Neon),
		part("EyeR", Vector3.new(0.3, 0.3, 0.2), CFrame.new(0.4 * s, 0.5 * s, -3.2 * s), Color3.fromRGB(255, 220, 90), Enum.Material.Neon),
	}
	for i = -1, 1 do
		part(
			"Thorn",
			Vector3.new(0.4, 1.2, 1),
			CFrame.new(0, 1.2 * s, i * 1.1 * s),
			Color3.fromRGB(60, 45, 35),
			Enum.Material.Wood,
			"Wedge"
		)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.MaxHealth = cfg.health
	humanoid.Health = cfg.health
	humanoid.WalkSpeed = cfg.walkSpeed
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	model.PrimaryPart = root

	local gui = Instance.new("BillboardGui")
	gui.Name = "HB_CreatureLabel"
	gui.Size = UDim2.fromOffset(160, 46)
	gui.StudsOffset = Vector3.new(0, 3 * s, 0)
	gui.MaxDistance = 90
	gui.Parent = root
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = cfg.displayName
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Parent = gui
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.fromOffset(20, 20)
	barBack.Size = UDim2.new(1, -40, 0, 6)
	barBack.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	barBack.BorderSizePixel = 0
	barBack.Parent = gui
	local bar = Instance.new("Frame")
	bar.Name = "Fill"
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Color3.fromRGB(200, 70, 60)
	bar.BorderSizePixel = 0
	bar.Parent = barBack
	local warning = Instance.new("TextLabel")
	warning.Name = "Warning"
	warning.Position = UDim2.fromOffset(0, 26)
	warning.Size = UDim2.new(1, 0, 0, 20)
	warning.BackgroundTransparency = 1
	warning.Text = "!"
	warning.Font = Enum.Font.GothamBlack
	warning.TextSize = 22
	warning.TextColor3 = TELEGRAPH_COLOR
	warning.TextStrokeTransparency = 0.2
	warning.Visible = false
	warning.Parent = gui

	return model, root, humanoid, { body = body, eyes = eyes, bar = bar, warning = warning }
end

-- Lifecycle ---------------------------------------------------------------------------------

local function updateBar(c)
	c.visual.bar.Size = UDim2.fromScale(math.clamp(c.health / c.cfg.health, 0, 1), 1)
	if c.humanoid.Parent then
		c.humanoid.Health = math.max(1, c.health) -- display only; the engine never kills creatures
	end
end

local function setTelegraph(c, on: boolean)
	c.visual.warning.Visible = on
	local color = if on then TELEGRAPH_COLOR else c.cfg.color
	TweenService:Create(c.visual.body, TweenInfo.new(0.15), { Color = color }):Play()
	for _, eye in c.visual.eyes do
		eye.Color = if on then TELEGRAPH_COLOR else Color3.fromRGB(255, 220, 90)
	end
end

local function remove(c)
	creatures[c.id] = nil
	c.pathToken += 1
	for _, connection in c.connections do
		connection:Disconnect()
	end
	if c.model.Parent then
		c.model:Destroy()
	end
end

local function lose(c, reason: string)
	if not c.alive then
		return
	end
	c.alive = false
	CreatureBrain.kill(c.brain)
	print(`[Hollowbound] {c.cfg.displayName} #{c.id} lost ({reason})`)
	remove(c)
	if c.onLost then
		task.spawn(c.onLost, c)
	end
end

local function defeat(c)
	if not c.alive then
		return
	end
	c.alive = false
	CreatureBrain.kill(c.brain)
	c.humanoid:Move(Vector3.zero)
	setTelegraph(c, false)
	c.visual.warning.Visible = false
	print(`[Hollowbound] {c.cfg.displayName} #{c.id} defeated`)
	for _, child in c.model:GetDescendants() do
		if child:IsA("BasePart") and child.Transparency < 1 then
			TweenService:Create(child, TweenInfo.new(Config.Creatures.FadeSeconds), { Transparency = 1 }):Play()
		end
	end
	task.delay(Config.Creatures.FadeSeconds, remove, c)
	if c.onDefeated then
		task.spawn(c.onDefeated, c)
	end
end

--[[
	Spawns a creature of `variant` standing on `position`. Returns the creature, or nil
	when MaxActive creatures already exist (callers retry later).
	options = { onDefeated = (creature) -> (), onLost = (creature) -> () }
]]
function Creatures.spawn(variant: string, position: Vector3, options)
	local cfg = Config.Creatures.Variants[variant]
	assert(cfg, "Unknown creature variant " .. tostring(variant))
	if count() >= Config.Creatures.MaxActive then
		return nil
	end
	nextId += 1
	local model, root, humanoid, visual = buildModel(cfg, position)
	model:SetAttribute("CreatureId", nextId)
	model:SetAttribute("Variant", variant)
	model:AddTag(Config.Tags.Creature)
	model.Parent = folder
	root:SetNetworkOwner(nil)

	local c = {
		id = nextId,
		variant = variant,
		cfg = cfg,
		model = model,
		root = root,
		humanoid = humanoid,
		visual = visual,
		radius = 1.6 * cfg.scale,
		home = position,
		health = cfg.health,
		alive = true,
		brain = CreatureBrain.new(os.clock()),
		path = PathfindingService:CreatePath({
			AgentRadius = 2 * cfg.scale,
			AgentHeight = 3 * cfg.scale,
			AgentCanJump = false,
			WaypointSpacing = 4,
		}),
		waypoints = nil,
		waypointIndex = 0,
		pathGoal = nil,
		lastComputeAt = -math.huge,
		pathToken = 0,
		pathFailures = 0,
		failuresFor = nil,
		lastProgressPos = position,
		lastProgressAt = os.clock(),
		patrolPoint = nil,
		strikeTarget = nil,
		connections = {},
		onDefeated = options and options.onDefeated,
		onLost = options and options.onLost,
	}
	creatures[c.id] = c
	table.insert(c.connections, humanoid.Died:Connect(function()
		lose(c, "engine death")
	end))
	table.insert(c.connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			lose(c, "removed from the world")
		end
	end))
	return c
end

-- Living creatures, for melee targeting: { id, model, root, radius }.
function Creatures.living()
	local list = {}
	for _, c in creatures do
		if c.alive and c.root.Parent then
			table.insert(list, c)
		end
	end
	return list
end

--[[
	Damage from a player's attack. Returns { position, killed } or nil if refused.
	The attacker is recorded only for logs: rewards never go to the last hitter.
]]
function Creatures.damage(id: number, amount: number, attacker: Player)
	local c = creatures[id]
	if not c or not c.alive or typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return nil
	end
	if Zones.isProtected(c.root.Position) then
		return nil
	end
	c.health -= amount
	updateBar(c)
	local flash = Instance.new("Highlight")
	flash.FillColor = Color3.new(1, 1, 1)
	flash.FillTransparency = 0.3
	flash.OutlineTransparency = 1
	flash.Parent = c.model
	task.delay(Config.Combat.HitFlashSeconds, function()
		flash:Destroy()
	end)
	local position = c.root.Position
	if c.health <= 0 then
		print(`[Hollowbound] {attacker.Name} landed the final hit on {c.cfg.displayName} #{c.id}`)
		defeat(c)
		return { position = position, killed = true }
	end
	-- Being hit makes an idle creature notice its attacker.
	if c.brain.state == "Idle" or c.brain.state == "Patrol" then
		c.provokedBy = attacker
	end
	return { position = position, killed = false }
end

function Creatures.despawn(id: number)
	local c = creatures[id]
	if c then
		c.alive = false
		remove(c)
	end
end

-- Perception ------------------------------------------------------------------------------

local function perceive(c, now: number, params: RaycastParams)
	local cfg = c.cfg
	local root = c.root
	local eye = root.Position + Vector3.new(0, 1.2 * cfg.scale, 0)
	local look = root.CFrame.LookVector
	local cosHalfFov = math.cos(math.rad(cfg.fovDegrees / 2))
	local targets = {}
	local anyNear = false
	for _, player in Players:GetPlayers() do
		local target = Characters.liveRoot(player)
		if not target then
			continue
		end
		local offset = target.Position - root.Position
		local distance = offset.Magnitude
		if distance <= Config.Creatures.DormantRadius then
			anyNear = true
		end
		if distance > cfg.detectRadius * 2 then
			continue
		end
		local visible = clearLine(eye, target.Position, params)
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local inFov = flat.Magnitude < 0.5 or flat.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit) >= cosHalfFov
		local provoked = c.provokedBy == player
		targets[player] = {
			distance = distance,
			visible = visible,
			noticeable = provoked or distance <= cfg.hearRadius or (visible and inFov and distance <= cfg.detectRadius),
			protected = Zones.isProtected(target.Position),
			condition = Vitals.condition(player),
			homeDistance = (target.Position - c.home).Magnitude,
			root = target,
		}
	end
	c.provokedBy = nil
	if c.brain.targetKey ~= c.failuresFor then
		c.pathFailures = 0
		c.failuresFor = c.brain.targetKey
	end
	return {
		now = now,
		distanceFromHome = (root.Position - c.home).Magnitude,
		selfProtected = Zones.isProtected(root.Position),
		patrolArrived = c.patrolPoint ~= nil and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(c.patrolPoint.X, 0, c.patrolPoint.Z)).Magnitude < 3,
		pathFailures = c.pathFailures,
		maxPathFailures = Config.Creatures.MaxPathFailures,
		targets = targets,
	}, anyNear
end

-- Movement --------------------------------------------------------------------------------

local function stop(c)
	c.humanoid:Move(Vector3.zero)
	c.humanoid:MoveTo(c.root.Position)
	c.waypoints = nil
end

local function pathFailed(c, why: string)
	c.pathFailures += 1
	c.waypoints = nil
	if c.pathFailures == Config.Creatures.MaxPathFailures then
		print(`[Hollowbound] {c.cfg.displayName} #{c.id} gave up a path ({why})`)
	end
end

local function computePath(c, goal: Vector3)
	c.lastComputeAt = os.clock()
	c.pathToken += 1
	local token = c.pathToken
	local start = c.root.Position
	task.spawn(function()
		local ok = pcall(function()
			c.path:ComputeAsync(start, goal)
		end)
		if token ~= c.pathToken or not c.alive then
			return -- a newer request or a removed creature: ignore this result
		end
		if not ok or c.path.Status ~= Enum.PathStatus.Success then
			pathFailed(c, "no path")
			return
		end
		local waypoints = c.path:GetWaypoints()
		for _, waypoint in waypoints do
			if Zones.isProtected(waypoint.Position) then
				pathFailed(c, "path enters a protected zone")
				return
			end
		end
		c.waypoints = waypoints
		c.waypointIndex = math.min(2, #waypoints)
		c.pathGoal = goal
	end)
end

local function navigate(c, goal: Vector3, now: number, params: RaycastParams)
	local root = c.root
	-- Progress check: no movement for StuckSeconds counts as a failure.
	if (root.Position - c.lastProgressPos).Magnitude > 1 then
		c.lastProgressPos = root.Position
		c.lastProgressAt = now
	elseif now - c.lastProgressAt > Config.Creatures.StuckSeconds then
		c.lastProgressAt = now
		pathFailed(c, "stuck")
	end

	if Zones.isProtected(goal) then
		pathFailed(c, "goal is protected")
		stop(c)
		return
	end
	local distance = (goal - root.Position).Magnitude
	if distance <= Config.Creatures.DirectChaseDistance and clearLine(root.Position, goal, params) then
		c.waypoints = nil
		c.humanoid:MoveTo(goal)
		return
	end
	local stale = c.pathGoal == nil or (goal - c.pathGoal).Magnitude > 4
	if (c.waypoints == nil or stale) and now - c.lastComputeAt >= Config.Creatures.RepathInterval then
		computePath(c, goal)
	end
	if c.waypoints then
		local waypoint = c.waypoints[c.waypointIndex]
		if waypoint and (Vector3.new(waypoint.Position.X, root.Position.Y, waypoint.Position.Z) - root.Position).Magnitude < 2.5 then
			c.waypointIndex += 1
			waypoint = c.waypoints[c.waypointIndex]
		end
		if waypoint then
			c.humanoid:MoveTo(waypoint.Position)
		else
			c.waypoints = nil
		end
	end
end

local function pickPatrolPoint(c): Vector3
	for _ = 1, 6 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(0.3, 1) * c.cfg.patrolRadius
		local point = c.home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		if not Zones.isProtected(point) then
			return point
		end
	end
	return c.home
end

-- Strike ------------------------------------------------------------------------------------

local function strike(c, params: RaycastParams)
	local player = c.strikeTarget
	c.strikeTarget = nil
	setTelegraph(c, false)
	c.humanoid.AutoRotate = true
	if not player or not player.Parent then
		return
	end
	local target = Characters.liveRoot(player)
	if not target or Vitals.condition(player) ~= "Alive" then
		return
	end
	local offset = target.Position - c.root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local reach = c.cfg.attackRange + c.radius + Config.Combat.RangeTolerance
	if flat.Magnitude > reach or math.abs(offset.Y) > reach then
		return -- the explorer stepped out of range: the telegraph worked
	end
	local look = c.root.CFrame.LookVector
	if flat.Magnitude > 1 and flat.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit) < math.cos(math.rad(c.cfg.attackArcDegrees / 2)) then
		return
	end
	if not clearLine(c.root.Position, target.Position, params) then
		return
	end
	local result = Vitals.damagePlayer(player, c.cfg.damage, { kind = "Creature", name = c.cfg.displayName })
	if result ~= "Refused" then
		ServerNet.combatFx(player, { kind = "Hurt", amount = c.cfg.damage, from = c.cfg.displayName })
	end
end

local function telegraph(c, targetPlayer: Player, targetRoot: BasePart)
	c.strikeTarget = targetPlayer
	stop(c)
	c.humanoid.AutoRotate = false
	local at = Vector3.new(targetRoot.Position.X, c.root.Position.Y, targetRoot.Position.Z)
	if (at - c.root.Position).Magnitude > 0.1 then
		c.root.CFrame = CFrame.lookAt(c.root.Position, at)
	end
	setTelegraph(c, true)
	for _, player in Players:GetPlayers() do
		local root = Characters.liveRoot(player)
		if root and (root.Position - c.root.Position).Magnitude <= WARN_RADIUS then
			ServerNet.combatFx(player, {
				kind = "Telegraph",
				name = c.cfg.displayName,
				duration = c.cfg.windup,
				targeted = player == targetPlayer,
			})
		end
	end
end

-- Update ------------------------------------------------------------------------------------

local function step(c, now: number, params: RaycastParams)
	if not c.alive then
		return
	end
	if c.root.Position.Y < workspace.FallenPartsDestroyHeight + 20 then
		lose(c, "fell out of the world")
		return
	end
	local perception, anyNear = perceive(c, now, params)
	if not anyNear and c.brain.state ~= "Return" and c.brain.state ~= "Windup" and c.brain.state ~= "Recover" then
		return -- dormant: nobody around
	end
	local previousState = c.brain.state
	local decision = CreatureBrain.step(c.brain, perception, c.cfg)

	if decision.telegraph then
		local t = perception.targets[c.brain.targetKey]
		if t then
			telegraph(c, c.brain.targetKey, t.root)
		end
	end
	if decision.strike then
		strike(c, params)
	end
	if decision.reset then
		c.health = c.cfg.health
		updateBar(c)
	end
	if c.brain.state ~= previousState and c.brain.state ~= "Windup" and c.humanoid.AutoRotate == false then
		c.humanoid.AutoRotate = true
	end
	c.humanoid.WalkSpeed = if c.brain.state == "Pursue" then c.cfg.pursuitSpeed else c.cfg.walkSpeed

	local move = decision.move
	if move == "Target" then
		local t = perception.targets[c.brain.targetKey]
		if t then
			navigate(c, t.root.Position, now, params)
		end
	elseif move == "Home" then
		navigate(c, c.home, now, params)
	elseif move == "Patrol" then
		if decision.newPatrol or not c.patrolPoint then
			c.patrolPoint = pickPatrolPoint(c)
		end
		navigate(c, c.patrolPoint, now, params)
	else
		if c.brain.state ~= "Patrol" then
			c.patrolPoint = nil
		end
		stop(c)
	end
end

function Creatures.start()
	folder = Instance.new("Folder")
	folder.Name = "HollowboundCreatures"
	folder.Parent = workspace

	task.spawn(function()
		while true do
			task.wait(Config.Creatures.TickInterval)
			local now = os.clock()
			local params = worldOnlyParams()
			for _, c in creatures do
				local ok, err = pcall(step, c, now, params)
				if not ok then
					warn(`[Hollowbound] Creature #{c.id} update failed: {err}`)
				end
			end
		end
	end)
end

return Creatures
