--[[
	Checks a world plan before (and after) installation. Pure: runs in Studio, on the
	server, and under Lune. Returns a list of problems (empty means valid) and a few facts.

	Checks:
	  - required markers exist exactly as often as the game needs them;
	  - the main route connects gate, camp, ruins, and floor (both directions: the graph is
	    undirected), every walkway slope is within the limit, every node is above the kill
	    plane;
	  - three-dimensional zones: the spawn and service stations are inside town; the shaft
	    column, the space under the terminal, and the space under the camp are not; the gate
	    landing is outside town (stepping onto it starts an expedition);
	  - decor and background never collide or block raycasts;
	  - creature dens sit farther from town and camps than their leash;
	  - the kill plane is below the floor and above FallenPartsDestroyHeight.
]]

local Geometry = require(script.Parent.Geometry)

local Validate = {}

local function tagged(plan, tag: string)
	local list = {}
	for _, name in plan.groupOrder do
		for _, spec in plan.groups[name].parts do
			for _, t in spec.tags or {} do
				if t == tag then
					table.insert(list, spec)
				end
			end
		end
	end
	return list
end
Validate.tagged = tagged

local function zoneContains(zones, point): boolean
	for _, z in zones do
		if Geometry.insideBox(point, z.pos, z.size, z.rot) then
			return true
		end
	end
	return false
end
Validate.zoneContains = zoneContains

-- options = { fallenPartsDestroyHeight = number?, leash = { Regular = n, Guardian = n } }
function Validate.check(plan, world, options)
	options = options or {}
	local problems = {}
	local function fail(message: string)
		table.insert(problems, message)
	end

	-- Required markers.
	local function expectCount(tag: string, count: number?, atLeast: number?)
		local n = #tagged(plan, tag)
		if count and n ~= count then
			fail(`expected exactly {count} part(s) tagged {tag}, found {n}`)
		elseif atLeast and n < atLeast then
			fail(`expected at least {atLeast} part(s) tagged {tag}, found {n}`)
		end
	end
	expectCount("HB_TownSpawn", 1)
	expectCount("HB_RegistrationTerminal", 1)
	expectCount("HB_ServiceStation", 1)
	expectCount("HB_SupplyStation", 1)
	expectCount("HB_TownZone", nil, 1)
	expectCount("HB_CampZone", nil, 1)
	expectCount("HB_Region", nil, 1)
	local regular, guardians, encounterIds = 0, 0, {}
	for _, spec in tagged(plan, "HB_CreatureSpawn") do
		local attrs = spec.attrs or {}
		if attrs.Variant == "Guardian" then
			guardians += 1
			if typeof(attrs.EncounterId) ~= "string" then
				fail(`guardian spawn {spec.name} has no EncounterId`)
			else
				encounterIds[attrs.EncounterId] = true
			end
		else
			regular += 1
		end
	end
	if regular < 1 then
		fail("no regular creature spawn")
	end
	if guardians ~= 1 then
		fail(`expected 1 guardian spawn, found {guardians}`)
	end
	for _, cache in tagged(plan, "HB_RelicCache") do
		local id = cache.attrs and cache.attrs.EncounterId
		if not encounterIds[id] then
			fail(`relic cache {cache.name} has no matching guardian (EncounterId {tostring(id)})`)
		end
	end
	expectCount("HB_RelicCache", 1)
	local relicNames = {}
	for _, spec in tagged(plan, "HB_RelicSpawn") do
		relicNames[spec.name] = (relicNames[spec.name] or 0) + 1
	end
	for _, name in { "RelicSpawnA", "RelicSpawnB", "RelicSpawnC", "RelicSpawnD", "RelicSpawnE" } do
		if relicNames[name] ~= 1 then
			fail(`expected exactly one {name}, found {relicNames[name] or 0}`)
		end
	end

	-- Route graph and slopes.
	local graph = {}
	for _, edge in plan.route.edges do
		graph[edge.a] = graph[edge.a] or {}
		graph[edge.b] = graph[edge.b] or {}
		table.insert(graph[edge.a], edge.b)
		table.insert(graph[edge.b], edge.a)
		if edge.slope > (options.maxSlope or 35) + 0.01 then
			fail(`route {edge.kind} {edge.a} -> {edge.b} is too steep ({math.floor(edge.slope)} degrees)`)
		end
		if edge.width < 6 then
			fail(`route {edge.kind} {edge.a} -> {edge.b} is too narrow ({edge.width})`)
		end
	end
	local seen, queue = { Gate = true }, { "Gate" }
	while #queue > 0 do
		local id = table.remove(queue, 1)
		for _, nextId in graph[id] or {} do
			if not seen[nextId] then
				seen[nextId] = true
				table.insert(queue, nextId)
			end
		end
	end
	for _, goal in { "Floor", "CampEdge", "CampExit", "RuinsLedge", "FloorLanding", "BridgeHead" } do
		if not seen[goal] then
			fail(`route: {goal} is not reachable from the Descent Gate`)
		end
	end
	local killY = plan.info.killY
	for id, pos in plan.route.nodes do
		if pos.Y <= killY + 20 then
			fail(`route node {id} is too close to the kill plane`)
		end
	end

	-- Zones.
	local townZones, campZones = tagged(plan, "HB_TownZone"), tagged(plan, "HB_CampZone")
	local spawn = tagged(plan, "HB_TownSpawn")[1]
	if spawn and not zoneContains(townZones, Geometry.add(spawn.pos, Geometry.v(0, 3, 0))) then
		fail("the town spawn is not inside a town zone")
	end
	for _, tag in { "HB_RegistrationTerminal", "HB_ServiceStation", "HB_SupplyStation" } do
		local station = tagged(plan, tag)[1]
		if station then
			if not zoneContains(townZones, Geometry.add(station.pos, Geometry.v(0, 1, 0))) then
				fail(`{station.name} is not inside a town zone`)
			end
			for _, below in { 8, 15, 40 } do
				local under = Geometry.add(station.pos, Geometry.v(0, -below, 0))
				if zoneContains(townZones, under) then
					fail(`{below} studs below {station.name} still counts as town`)
				end
			end
		end
	end
	for depth = 0, world.FloorDepth, 20 do
		for _, r in { 0, 60, 120, 170 } do
			for _, angle in { 0, 90, 180, 270 } do
				local p = Geometry.polar(r, angle, -depth - 3)
				if zoneContains(townZones, p) then
					fail(`shaft point (r {r}, depth {depth}) counts as town`)
				end
				if zoneContains(campZones, p) and r < 150 then
					fail(`shaft point (r {r}, depth {depth}) counts as a camp`)
				end
			end
		end
	end
	local campDepth = plan.info.campDepth
	for _, zone in campZones do
		local surface = Geometry.v(zone.pos.X, -campDepth + 3, zone.pos.Z)
		if not zoneContains(campZones, surface) then
			fail(`{zone.name}: standing on the camp shelf does not count as camp`)
		end
		local under = Geometry.v(zone.pos.X, -campDepth - 8, zone.pos.Z)
		if zoneContains(campZones, under) then
			fail(`{zone.name}: 8 studs below the camp shelf still counts as camp`)
		end
	end
	local gate = plan.route.nodes.Gate
	if gate and zoneContains(townZones, Geometry.add(gate, Geometry.v(0, 3, 0))) then
		fail("the gate landing counts as town; stepping onto it should start an expedition")
	end

	-- Decor and background never collide or block raycasts.
	for _, name in plan.groupOrder do
		for _, spec in plan.groups[name].parts do
			if (spec.role == "Decor" or spec.role == "Background") and (spec.collide or spec.query) then
				fail(`{spec.name} is {spec.role} but collides or blocks raycasts`)
			end
			if spec.role == "Zone" and (spec.collide or spec.query or spec.transparency < 1) then
				fail(`{spec.name} is a zone but is visible, collides, or blocks raycasts`)
			end
		end
	end

	-- Dens farther than their leash from protected zones.
	local leash = options.leash or {}
	for _, den in tagged(plan, "HB_CreatureSpawn") do
		local variant = (den.attrs and den.attrs.Variant) or "Regular"
		local radius = leash[variant] or 0
		for _, zone in campZones do
			local halfDiagonal = Geometry.length(Geometry.scale(zone.size, 0.5))
			if Geometry.length(Geometry.sub(den.pos, zone.pos)) - halfDiagonal < radius then
				fail(`{den.name} is within its leash ({radius}) of {zone.name}`)
			end
		end
		if den.pos.Y > -world.FloorDepth + 50 then
			-- dens on the floor are far below town; anything else must be checked by hand
			fail(`{den.name} is not on the floor; check its leash against town by hand`)
		end
	end

	-- Kill plane.
	if killY >= -world.FloorDepth - 20 then
		fail("the kill plane is not below the floor")
	end
	local fallen = options.fallenPartsDestroyHeight
	if fallen and world.Origin.Y + killY <= fallen + 20 then
		fail(`the kill plane (Y {world.Origin.Y + killY}) is below FallenPartsDestroyHeight (+20)`)
	end
	if world.Origin.Y - world.LowerDarkDepth <= (fallen or -500) + 20 then
		fail("background scenery reaches FallenPartsDestroyHeight")
	end

	return problems
end

return Validate
