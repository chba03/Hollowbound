--[[
	Rope deployment and climbing validation. Server side.

	Each plot has a RopeAnchor hanging over the pit. The owner deploys the rope at the
	plot's winch (RopeMount prompt); it then extends to the player's rope length and
	follows later length upgrades. Climbing:

	  - The client moves its own character along the rope (smooth, no input lag) with
	    constraints, at the speed in its HB_RopeSpeed attribute. See client RopeController.
	  - The server owns the HB_OnRope state and checks every climber each
	    Config.Rope.CheckInterval: they must stay near the rope line, inside its span,
	    and within the allowed speed. Violations snap the character back to its last
	    valid position.
	  - Rope length decides how deep you can climb. Nothing stops a fall past the
	    rope's end: you free fall, and a long fall is fatal (FallDamage). That is what
	    gates the deeper layers.

	Rope range: from rim height - rope length (bottom) to rim height + TopOffset (top).
	Reaching the top while climbing returns the player to their plot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Progression"))
local Characters = require(script.Parent.Characters)
local Hollow = require(script.Parent.Hollow)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local ServerNet = require(script.Parent.ServerNet)

local RopeService = {}

type Session = {
	plot: Model,
	anchor: BasePart,
	deployed: boolean,
	onRope: boolean,
	lastPos: Vector3?,
	lastTime: number,
	graceUntil: number,
	strikes: number,
	bottom: Attachment?,
}

local sessions: { [Player]: Session } = {}

-- Geometry ----------------------------------------------------------------------------

local function ropeLength(player: Player): number
	local length = player:GetAttribute("HB_RopeLength")
	return if typeof(length) == "number" then length else Progression.value("RopeLength", 1)
end

local function ropeSpeed(player: Player): number
	local speed = player:GetAttribute("HB_RopeSpeed")
	return if typeof(speed) == "number" then speed else Progression.value("RopeSpeed", 1)
end

local function pivot(player: Player, cframe: CFrame)
	local character = player.Character
	if character then
		character:PivotTo(cframe)
	end
end

-- Returns rope x/z, top Y, and bottom Y for the player's rope.
local function span(player: Player, session: Session): (number, number, number, number)
	local rimY = (Hollow.center() :: Vector3).Y
	local anchor = session.anchor.Position
	return anchor.X, anchor.Z, rimY + Config.Rope.TopOffset, rimY - ropeLength(player)
end

-- Faces the climber toward the pit wall.
local function climbCFrame(x: number, y: number, z: number): CFrame
	local center = Hollow.center() :: Vector3
	local outward = Vector3.new(x - center.X, 0, z - center.Z)
	outward = if outward.Magnitude > 0.01 then outward.Unit else Vector3.zAxis
	local position = Vector3.new(x, y, z)
	return CFrame.lookAt(position, position + outward)
end

-- Visuals -----------------------------------------------------------------------------

local function bottomOffset(player: Player, session: Session): Vector3
	local rimY = (Hollow.center() :: Vector3).Y
	return Vector3.new(0, (rimY - ropeLength(player)) - session.anchor.Position.Y, 0)
end

local function buildRope(session: Session)
	local anchor = session.anchor
	local top = Instance.new("Attachment")
	top.Name = "RopeTop"
	top.Parent = anchor
	local bottom = Instance.new("Attachment")
	bottom.Name = "RopeBottom"
	bottom.Parent = anchor

	local beam = Instance.new("Beam")
	beam.Name = "Rope"
	beam.Attachment0 = top
	beam.Attachment1 = bottom
	beam.Width0 = 0.35
	beam.Width1 = 0.35
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Color = ColorSequence.new(Color3.fromRGB(150, 115, 70))
	beam.LightInfluence = 1
	beam.Parent = anchor

	session.bottom = bottom
end

local function clearRope(session: Session)
	for _, name in { "RopeTop", "RopeBottom", "Rope" } do
		local child = session.anchor:FindFirstChild(name)
		if child then
			child:Destroy()
		end
	end
	session.bottom = nil
end

-- Extends (or shortens) the rope to the player's current length.
local function extendRope(player: Player, session: Session, animate: boolean)
	if not session.bottom then
		buildRope(session)
	end
	local goal = bottomOffset(player, session)
	if animate then
		TweenService:Create(
			session.bottom :: Attachment,
			TweenInfo.new(Config.Rope.DeploySeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = goal }
		):Play()
	else
		(session.bottom :: Attachment).Position = goal
	end
end

local function updatePrompt(session: Session)
	local mount = session.plot:FindFirstChild("RopeMount")
	local prompt = mount and mount:FindFirstChild("RopePrompt")
	if prompt then
		prompt.ActionText = if session.deployed then "Climb down" else "Deploy rope"
	end
end

-- State changes -----------------------------------------------------------------------

function RopeService.deploy(player: Player, animate: boolean)
	local session = sessions[player]
	if not session or session.deployed then
		return
	end
	session.deployed = true
	player:SetAttribute("HB_RopeDeployed", true)
	-- Start from the anchor so the extension is visible.
	if not session.bottom then
		buildRope(session)
	end
	extendRope(player, session, animate)
	updatePrompt(session)
end

-- Puts the player on their rope at height y (clamped to the rope's span).
function RopeService.attach(player: Player, y: number)
	local session = sessions[player]
	local root = Characters.liveRoot(player)
	if not session or not root or not Hollow.center() then
		return
	end
	local x, z, topY, bottomY = span(player, session)
	local cf = climbCFrame(x, math.clamp(y, bottomY, topY), z)
	root.AssemblyLinearVelocity = Vector3.zero
	pivot(player, cf)

	session.onRope = true
	session.lastPos = cf.Position
	session.lastTime = os.clock()
	session.graceUntil = os.clock() + 0.6 -- let the client's position catch up
	player:SetAttribute("HB_OnRope", true)
end

function RopeService.detach(player: Player)
	local session = sessions[player]
	if session and session.onRope then
		session.onRope = false
		player:SetAttribute("HB_OnRope", false)
	end
end

-- Request handlers ----------------------------------------------------------------------

local function onWinch(player: Player, plot: Model, mount: BasePart)
	local session = sessions[player]
	if not session or session.plot ~= plot then
		ServerNet.notify(player, "This isn't your rope.", "error")
		return
	end
	local root = Characters.liveRoot(player)
	if not root or (root.Position - mount.Position).Magnitude > Config.Base.InteractMaxDistance then
		return
	end
	if not session.deployed then
		RopeService.deploy(player, true)
		ServerNet.notify(player, `Rope deployed: {ropeLength(player)} studs. Use the winch again to climb down.`, "success")
		return
	end
	RopeService.attach(player, (Hollow.center() :: Vector3).Y - Config.Rope.MountDepth)
	ServerNet.notify(player, "W / S to climb, Space to let go.", "info")
end

local function onGrab(player: Player)
	local session = sessions[player]
	local root = Characters.liveRoot(player)
	if not session or not session.deployed or session.onRope or not root or not Hollow.center() then
		return
	end
	local x, z, topY, bottomY = span(player, session)
	local position = root.Position
	local horizontal = Vector2.new(position.X - x, position.Z - z).Magnitude
	if horizontal > Config.Rope.ServerGrabRadius or position.Y < bottomY - 4 or position.Y > topY + 4 then
		ServerNet.notify(player, "Too far from your rope to grab it.", "error")
		return
	end
	RopeService.attach(player, position.Y)
end

-- Climbing off at the top: off the rope and back onto the plot.
local function dismountTop(player: Player)
	RopeService.detach(player)
	Plots.sendHome(player)
end

local function onRelease(player: Player, atTop: any)
	local session = sessions[player]
	if not session or not session.onRope then
		return
	end
	local root = Characters.liveRoot(player)
	if atTop == true then
		-- Only honour it near the top. Otherwise ignore it and keep the player on the
		-- rope: dropping them here would send them down the pit.
		if root and Hollow.center() then
			local _, _, topY = span(player, session)
			if root.Position.Y >= topY - Config.Rope.ServerTopReach then
				dismountTop(player)
			end
		end
		return
	end
	RopeService.detach(player)
end

-- Validation loop -----------------------------------------------------------------------

local function check(player: Player, session: Session, now: number)
	local root = Characters.liveRoot(player)
	if not root then
		RopeService.detach(player)
		return
	end
	local position = root.Position
	local depth, _, inPit = Hollow.measure(position)
	if not depth then
		return
	end
	PlayerData.recordDepth(player, depth)

	if not inPit and depth > Config.Hollow.SeaRecoverDepth then
		-- Fell off the island's cliffs into the forest below: there is no way back up.
		RopeService.detach(player)
		Plots.sendHome(player)
		ServerNet.notify(player, "You fell from the cliffs and climbed back to your base.", "info")
		return
	end

	if inPit and depth > 0 and not session.deployed then
		-- Jumped into the pit without deploying: the rope follows so nobody is stranded.
		RopeService.deploy(player, false)
		ServerNet.notify(player, "Your rope unspooled after you.", "info")
	end

	if not session.onRope then
		return
	end
	if now < session.graceUntil then
		session.lastPos = position
		session.lastTime = now
		return
	end

	local x, z, topY, bottomY = span(player, session)
	if position.Y >= topY - Config.Rope.TopReach then
		-- Reached the top of the rope: always climb off onto the plot.
		dismountTop(player)
		return
	end
	local lastPos = session.lastPos or position
	local elapsed = math.max(now - session.lastTime, 1 / 60)
	local maxStep = ropeSpeed(player) * Config.Rope.DescendMultiplier * Config.Rope.SpeedTolerance * elapsed
		+ Config.Rope.SpeedSlack
	local horizontal = Vector2.new(position.X - x, position.Z - z).Magnitude
	local step = math.abs(position.Y - lastPos.Y)

	if
		horizontal > Config.Rope.MaxHorizontalDrift
		or step > maxStep
		or position.Y > topY + 6
		or position.Y < bottomY - 6
	then
		session.strikes += 1
		local safeY = math.clamp(lastPos.Y, bottomY, topY)
		pivot(player, climbCFrame(x, safeY, z))
		session.lastPos = Vector3.new(x, safeY, z)
		print(
			string.format(
				"[Hollowbound] Rope snap-back for %s (drift %.1f, step %.1f/%.1f, strikes %d)",
				player.Name,
				horizontal,
				step,
				maxStep,
				session.strikes
			)
		)
	else
		session.lastPos = position
	end
	session.lastTime = now
end

-- Wiring ------------------------------------------------------------------------------

local function onAssigned(player: Player, plot: Model)
	local anchor = plot:FindFirstChild("RopeAnchor")
	if not (anchor and anchor:IsA("BasePart")) or not Hollow.center() then
		warn(`[Hollowbound] {plot.Name} has no RopeAnchor (or no Hollow); ropes disabled for {player.Name}.`)
		return
	end
	local session: Session = {
		plot = plot,
		anchor = anchor,
		deployed = false,
		onRope = false,
		lastPos = nil,
		lastTime = 0,
		graceUntil = 0,
		strikes = 0,
		bottom = nil,
	}
	sessions[player] = session

	local rimY = (Hollow.center() :: Vector3).Y
	player:SetAttribute("HB_RopePoint", Vector3.new(anchor.Position.X, rimY, anchor.Position.Z))
	player:SetAttribute("HB_RopeDeployed", false)
	player:SetAttribute("HB_OnRope", false)
	updatePrompt(session)

	player:GetAttributeChangedSignal("HB_RopeLength"):Connect(function()
		if sessions[player] == session and session.deployed then
			extendRope(player, session, true)
		end
	end)
	player.CharacterAdded:Connect(function()
		RopeService.detach(player)
	end)
end

local function onReleased(player: Player, plot: Model)
	local session = sessions[player]
	if session and session.plot == plot then
		clearRope(session)
		session.deployed = false
		updatePrompt(session)
	end
	sessions[player] = nil
end

function RopeService.start()
	for _, plot in Plots.all() do
		local mount = plot:FindFirstChild("RopeMount")
		if mount and mount:IsA("BasePart") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "RopePrompt"
			prompt.ActionText = "Deploy rope"
			prompt.ObjectText = "Rope winch"
			prompt.MaxActivationDistance = 10
			prompt.HoldDuration = 0.3
			prompt.RequiresLineOfSight = false
			prompt.Parent = mount
			prompt.Triggered:Connect(function(player)
				onWinch(player, plot, mount)
			end)
		end
	end

	Plots.onAssigned(onAssigned)
	Plots.onReleased(onReleased)
	for _, player in Players:GetPlayers() do
		local plot = Plots.get(player)
		if plot and not sessions[player] then
			onAssigned(player, plot)
		end
	end

	ServerNet.on(Net.RopeGrab, onGrab)
	ServerNet.on(Net.RopeRelease, onRelease)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < Config.Rope.CheckInterval then
			return
		end
		accumulated = 0
		local now = os.clock()
		for player, session in sessions do
			check(player, session, now)
		end
	end)
end

return RopeService
