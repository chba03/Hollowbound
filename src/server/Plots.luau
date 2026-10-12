--[[
	Plot allocation: each player gets one of the rim plots when they join and gives it
	back when they leave. Plots are Models tagged Tags.Plot with a PlotIndex attribute.

	Expected children of a plot model (the dev map builds these; a hand-built plot
	needs the same names):
	  Floor, Stand            ground and the point players appear at
	  RopeAnchor              rope top, hanging over the pit; RopeMount (winch prompt)
	  Terminal                registry terminal (tagged Tags.RegistrationTerminal)
	  Pedestal1..PedestalN    display pedestals, N = Config.Base.PedestalCount
	  UpgradeRopeLength, UpgradeRopeSpeed, UpgradeBaseSlots   upgrade prompts
	  Sign                    BasePart holding a BillboardGui with a TextLabel

	The allocator itself is plain Luau so the self-test can check it.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Characters = require(script.Parent.Characters)

local Plots = {}

-- Pure allocator --------------------------------------------------------------------

local Allocator = {}
Allocator.__index = Allocator

function Plots.newAllocator(count: number)
	return setmetatable({ count = count, owners = {}, byUser = {} }, Allocator)
end

-- Returns the player's plot index, assigning the lowest free one. nil when full.
function Allocator:claim(userId: number): number?
	local existing = self.byUser[userId]
	if existing then
		return existing
	end
	for index = 1, self.count do
		if self.owners[index] == nil then
			self.owners[index] = userId
			self.byUser[userId] = index
			return index
		end
	end
	return nil
end

-- Frees the player's plot. Returns the index that was freed, or nil.
function Allocator:release(userId: number): number?
	local index = self.byUser[userId]
	if index then
		self.owners[index] = nil
		self.byUser[userId] = nil
	end
	return index
end

function Allocator:ownerOf(index: number): number?
	return self.owners[index]
end

-- Roblox wiring ---------------------------------------------------------------------

local allocator
local plotModels: { [number]: Model } = {}
local assignedHandlers: { (Player, Model) -> () } = {}
local releasedHandlers: { (Player, Model) -> () } = {}

local function setSign(plot: Model, text: string)
	local sign = plot:FindFirstChild("Sign")
	local label = sign and sign:FindFirstChildWhichIsA("BillboardGui", true)
	label = label and label:FindFirstChildWhichIsA("TextLabel")
	if label then
		label.Text = text
	end
end

-- Moves the character onto the player's plot.
function Plots.sendHome(player: Player)
	local plot = Plots.get(player)
	local character = player.Character
	local stand = plot and plot:FindFirstChild("Stand")
	if character and stand and stand:IsA("BasePart") then
		character:PivotTo(stand.CFrame * CFrame.new(0, 3, 0))
	end
end

local function onCharacterAdded(player: Player)
	-- Wait for the root so the pivot moves the whole rig.
	task.defer(function()
		local deadline = os.clock() + 5
		while not Characters.liveRoot(player) and os.clock() < deadline do
			task.wait()
		end
		Plots.sendHome(player)
	end)
end

local function assign(player: Player)
	local index = allocator:claim(player.UserId)
	if not index then
		player:Kick("This server's plots are all taken. Please join another server.")
		return
	end
	local plot = plotModels[index]
	plot:SetAttribute("OwnerUserId", player.UserId)
	player:SetAttribute("HB_PlotIndex", index)
	setSign(plot, `{player.DisplayName}'s base`)

	player.CharacterAdded:Connect(function()
		onCharacterAdded(player)
	end)
	if player.Character then
		onCharacterAdded(player)
	end

	for _, handler in assignedHandlers do
		task.spawn(handler, player, plot)
	end
	print(`[Hollowbound] Assigned plot {index} to {player.Name}`)
end

local function release(player: Player)
	local index = allocator:release(player.UserId)
	if not index then
		return
	end
	local plot = plotModels[index]
	plot:SetAttribute("OwnerUserId", nil)
	setSign(plot, `Plot {index}: vacant`)
	for _, handler in releasedHandlers do
		handler(player, plot)
	end
	print(`[Hollowbound] Released plot {index} from {player.Name}`)
end

function Plots.start()
	for _, instance in CollectionService:GetTagged(Config.Tags.Plot) do
		local index = instance:GetAttribute("PlotIndex")
		if instance:IsA("Model") and typeof(index) == "number" then
			plotModels[index] = instance
			-- Keep plots (and the ropes hanging from them) loaded for every client,
			-- even deep in the Hollow where streaming would otherwise unload them.
			pcall(function()
				instance.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
			end)
			setSign(instance, `Plot {index}: vacant`)
		end
	end

	local count = 0
	while plotModels[count + 1] do
		count += 1
	end
	if count < Config.Plots.Count then
		warn(`[Hollowbound] Found {count} plots tagged {Config.Tags.Plot}; Config.Plots.Count is {Config.Plots.Count}.`)
	end
	allocator = Plots.newAllocator(count)

	Players.PlayerAdded:Connect(assign)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		assign(player)
	end
end

function Plots.get(player: Player): Model?
	local index = allocator and allocator.byUser[player.UserId]
	return if index then plotModels[index] else nil
end

-- The player who owns a plot model, if any.
function Plots.ownerOf(plot: Model): Player?
	local userId = plot:GetAttribute("OwnerUserId")
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

function Plots.all(): { [number]: Model }
	return plotModels
end

function Plots.onAssigned(handler: (Player, Model) -> ())
	table.insert(assignedHandlers, handler)
end

function Plots.onReleased(handler: (Player, Model) -> ())
	table.insert(releasedHandlers, handler)
end

return Plots
