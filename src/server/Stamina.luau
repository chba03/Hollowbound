--[[
	Sprinting and stamina, server side (for fleeing or fighting the Hollow's creatures
	later).

	The client only says whether the sprint key is held (Net.Sprint). The server owns
	stamina and the character's WalkSpeed: a player sprints while they want to, are
	moving, are not on the rope, and have stamina left. Sprinting drains stamina;
	after a short pause it regenerates. Once empty, sprinting needs Config.Sprint.MinToStart
	stamina again, so tapping the key at zero does nothing.

	Published attributes for the HUD: HB_Stamina (0..MaxStamina, whole numbers) and
	HB_Sprinting (bool). Open: every number in Config.Sprint.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Perks = require(Shared:WaitForChild("Perks"))
local Characters = require(script.Parent.Characters)
local ServerNet = require(script.Parent.ServerNet)

local Stamina = {}

type State = {
	stamina: number,
	wants: boolean,
	sprinting: boolean,
	lastDrain: number, -- os.clock() when stamina was last spent
	published: number,
}

local states: { [Player]: State } = {}

local function stateFor(player: Player): State
	local state = states[player]
	if not state then
		state = {
			stamina = Config.Sprint.MaxStamina,
			wants = false,
			sprinting = false,
			lastDrain = 0,
			published = -1,
		}
		states[player] = state
	end
	return state
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function setSprinting(player: Player, state: State, sprinting: boolean)
	if state.sprinting == sprinting then
		return
	end
	state.sprinting = sprinting
	player:SetAttribute("HB_Sprinting", sprinting)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = if sprinting then Config.Sprint.SprintSpeed else Config.Sprint.WalkSpeed
	end
end

local function publish(player: Player, state: State)
	local rounded = math.floor(state.stamina + 0.5)
	if rounded ~= state.published then
		state.published = rounded
		player:SetAttribute("HB_Stamina", rounded)
	end
end

local function step(player: Player, state: State, dt: number, now: number)
	local cfg = Config.Sprint
	local root = Characters.liveRoot(player)
	local velocity = if root then root.AssemblyLinearVelocity else Vector3.zero
	local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > cfg.MovingSpeed
	local onRope = player:GetAttribute("HB_OnRope") == true

	local canStart = state.sprinting or state.stamina >= cfg.MinToStart
	local sprinting = root ~= nil and state.wants and moving and not onRope and state.stamina > 0 and canStart
	setSprinting(player, state, sprinting)

	if sprinting then
		state.stamina = math.max(0, state.stamina - cfg.DrainPerSecond * Perks.staminaDrain(player) * dt)
		state.lastDrain = now
		if state.stamina <= 0 then
			setSprinting(player, state, false)
		end
	elseif now - state.lastDrain >= cfg.RegenDelay then
		state.stamina = math.min(cfg.MaxStamina, state.stamina + cfg.RegenPerSecond * Perks.staminaRegen(player) * dt)
	end
	publish(player, state)
end

function Stamina.start()
	ServerNet.on(Net.Sprint, function(player: Player, wants: any)
		stateFor(player).wants = wants == true
	end)

	local function onCharacter(player: Player, character: Model)
		local state = stateFor(player)
		state.stamina = Config.Sprint.MaxStamina
		state.sprinting = false
		player:SetAttribute("HB_Sprinting", false)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.WalkSpeed = Config.Sprint.WalkSpeed
		end
	end
	local function onPlayer(player: Player)
		stateFor(player)
		player:SetAttribute("HB_Stamina", Config.Sprint.MaxStamina)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < Config.Sprint.TickSeconds then
			return
		end
		local elapsed = accumulated
		accumulated = 0
		local now = os.clock()
		for player, state in states do
			if player.Parent then
				step(player, state, elapsed, now)
			end
		end
	end)
end

return Stamina
