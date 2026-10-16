--[[
	Turns World/Layout + Config.World into a build plan. Pure: no Roblox APIs, so the same
	plan is produced in Studio, on the server, and under Lune. The Installer instantiates
	it; Validate checks it.

	plan = {
		groups = { [name] = { name, parts = { spec } } }, groupOrder = { name },
		route = { nodes = { [id] = pos }, edges = { { a, b, kind, width, slope } } },
		info = { campDepth, floorY, killY, lowerDarkY },
	}
	spec = {
		class = "Part" | "WedgePart" | "TrussPart" | "SpawnLocation", name, size, pos,
		rot = { x, y, z } (degrees, fromOrientation order), material, color (palette key or
		{ r, g, b }), transparency, collide, query, touch, shadow, shape ("Ball" |
		"Cylinder"), tags, attrs, props (other properties), extras = { { class, props,
		children } }, role ("Surface" | "Decor" | "Background" | "Marker" | "Zone")
	}
	All positions are relative to the world origin; the Installer adds the origin.
]]

local Geometry = require(script.Parent.Geometry)

local v, add, sub, scale = Geometry.v, Geometry.add, Geometry.sub, Geometry.scale
local polar, rotate = Geometry.polar, Geometry.rotate

local Planner = {}

local function newPlan()
	return { groups = {}, groupOrder = {}, route = { nodes = {}, edges = {} }, info = {} }
end

local function groupOf(plan, name: string)
	local g = plan.groups[name]
	if not g then
		g = { name = name, parts = {} }
		plan.groups[name] = g
		table.insert(plan.groupOrder, name)
	end
	return g
end

local function put(plan, groupName: string, spec)
	spec.class = spec.class or "Part"
	spec.rot = spec.rot or { x = 0, y = 0, z = 0 }
	spec.material = spec.material or "SmoothPlastic"
	spec.transparency = spec.transparency or 0
	if spec.collide == nil then
		spec.collide = true
	end
	if spec.query == nil then
		spec.query = true
	end
	if spec.shadow == nil then
		spec.shadow = true
	end
	spec.touch = spec.touch or false
	spec.role = spec.role or "Surface"
	table.insert(groupOf(plan, groupName).parts, spec)
	return spec
end

-- Decorative parts: never collide, never block raycasts (so drops, pathing, and line of
-- sight only use real ground and walls).
local function decor(spec)
	spec.collide = false
	spec.query = false
	spec.role = "Decor"
	return spec
end

local function background(spec)
	spec.collide = false
	spec.query = false
	spec.shadow = false
	spec.role = "Background"
	return spec
end

-- Text sign as a BillboardGui extra.
local function signExtra(text: string, height: number, color)
	return {
		class = "BillboardGui",
		props = { Size = { udim2 = { 0, 260, 0, 46 } }, StudsOffset = { v3 = { 0, height, 0 } }, MaxDistance = 140 },
		children = {
			{
				class = "TextLabel",
				props = {
					Size = { udim2 = { 1, 0, 1, 0 } },
					BackgroundTransparency = 1,
					Text = text,
					TextScaled = true,
					FontFace = { font = "GothamBold" },
					TextColor3 = { rgb = color or { 250, 240, 220 } },
					TextStrokeTransparency = 0.4,
				},
			},
		},
	}
end

local function lightExtra(brightness: number, range: number, color)
	return { class = "PointLight", props = { Brightness = brightness, Range = range, Color = { rgb = color }, Shadows = false } }
end

-- World shape ---------------------------------------------------------------------------------

local function profileAt(layout, depth: number): number
	local profile = layout.ShaftProfile
	if depth <= profile[1].depth then
		return profile[1].radius
	end
	for i = 1, #profile - 1 do
		local a, b = profile[i], profile[i + 1]
		if depth <= b.depth then
			local t = (depth - a.depth) / (b.depth - a.depth)
			return a.radius + (b.radius - a.radius) * t
		end
	end
	return profile[#profile].radius
end

local function wobble(layout, angle: number): number
	local total = 0
	for _, w in layout.Wobble do
		total += w.amplitude * math.sin(w.lobes * math.rad(angle) + w.phase)
	end
	return total
end

local function segmentCenter(layout, angle: number): number
	local step = 360 / layout.WallSegments
	return (math.floor((angle % 360) / step) + 0.5) * step
end

-- Radius of wall ring `ring` (0-based) at a segment-center angle.
local function ringRadius(layout, ring: number, angle: number): number
	local top, bottom = ring * layout.RingHeight, (ring + 1) * layout.RingHeight
	local widest = math.max(profileAt(layout, top), profileAt(layout, bottom), profileAt(layout, (top + bottom) / 2))
	for _, point in layout.ShaftProfile do
		if point.depth > top and point.depth < bottom then
			widest = math.max(widest, point.radius)
		end
	end
	return widest + wobble(layout, segmentCenter(layout, angle))
end

-- The innermost wall face near (angle, depth): routes are placed relative to this, so
-- no wall ring or segment can protrude into a path.
local function clearRadius(layout, angle: number, depth: number): number
	local best = math.huge
	local step = 360 / layout.WallSegments
	for dDepth = depth - 28, depth + 22, 10 do
		local ring = math.clamp(math.floor(math.max(0, dDepth) / layout.RingHeight), 0, 100)
		for dAngle = -12, 12, 4 do
			local a = angle + dAngle
			best = math.min(best, ringRadius(layout, ring, a))
		end
	end
	local _ = step
	return best
end

Planner.profileAt = profileAt
Planner.clearRadius = clearRadius

-- Slab whose top surface runs from a to b (both top-surface points).
local function slabBetween(a, b, width: number, thickness: number, overlap: number?)
	local d = sub(b, a)
	local flat = Geometry.flatLength(d)
	local yaw = Geometry.yawFacing(d.X, d.Z)
	local pitch = math.deg(math.atan2(d.Y, flat))
	local up = rotate(v(0, 1, 0), pitch, yaw, 0)
	local mid = Geometry.lerp(a, b, 0.5)
	return {
		size = v(width, thickness, Geometry.length(d) + (overlap or 1)),
		pos = sub(mid, scale(up, thickness / 2)),
		rot = { x = pitch, y = yaw, z = 0 },
		slope = math.deg(math.atan2(math.abs(d.Y), math.max(flat, 1e-6))),
	}
end

-- Local frame helper: place a box at offset (x along tangent/right, y up, z back) from an
-- anchor whose front faces `yaw`.
local function framed(anchor, yaw: number, offset, size)
	return { pos = add(anchor, rotate(offset, 0, yaw, 0)), size = size, rot = { x = 0, y = yaw, z = 0 } }
end

local function merge(base, extra)
	for k, val in extra do
		base[k] = val
	end
	return base
end

-- Shaft walls -----------------------------------------------------------------------------------

local function buildWalls(plan, layout, world)
	local step = 360 / layout.WallSegments
	local rings = math.ceil((world.FloorDepth + 20) / layout.RingHeight)
	for ring = 0, rings - 1 do
		local groupName = if ring < rings / 2 then "Shaft_WallsUpper" else "Shaft_WallsLower"
		local yTop = -ring * layout.RingHeight
		for segment = 0, layout.WallSegments - 1 do
			local angle = (segment + 0.5) * step
			local radius = ringRadius(layout, ring, angle)
			local thickness = layout.WallThickness
			local chord = 2 * (radius + thickness) * math.sin(math.rad(step / 2)) + 4
			local center = polar(radius + thickness / 2, angle, yTop - layout.RingHeight / 2)
			local tone = Geometry.hash(ring, segment)
			put(plan, groupName, {
				name = `Wall_{ring}_{segment}`,
				size = v(chord, layout.RingHeight + 4, thickness),
				pos = center,
				rot = { x = 0, y = Geometry.yawFacing(-center.X, -center.Z), z = 0 },
				material = if tone < 0.5 then "Limestone" else "Slate",
				color = if ring >= 3 and tone > 0.6 then "MossStone" elseif tone < 0.5 then "PaleStone" else "WeatheredStone",
			})
		end
	end
end

-- Rim town -------------------------------------------------------------------------------------

local function inRanges(angle: number, ranges): boolean
	angle %= 360
	for _, r in ranges do
		if angle >= r.from and angle <= r.to then
			return true
		end
	end
	return false
end

local function buildBuilding(plan, layout, b, groupName: string)
	-- Anchor: front-center on the rim surface; the building extends away from the shaft.
	local anchor = polar(b.radius - b.depth / 2, b.angle, 0)
	local yaw = Geometry.yawFacing(-anchor.X, -anchor.Z) -- front faces the shaft
	local W, D = b.width, b.depth
	local floors = b.floors or 1
	local storey = 9
	local function box(name, offset, size, extra)
		put(plan, groupName, merge(merge({ name = `{b.name}_{name}` }, framed(anchor, yaw, offset, size)), extra))
	end
	local h = floors * storey
	if b.kind == "Tower" then
		box("Base", v(0, 3, 0), v(W, 6, D), { material = "Cobblestone", color = "WeatheredStone" })
		box("Shaft", v(0, 6 + h / 2, 0), v(W - 2, h, D - 2), { material = "Limestone", color = "PaleStone" })
		box("Cap", v(0, 7 + h, 0), v(W + 2, 2, D + 2), { material = "WoodPlanks", color = "Timber" })
		box("Roof1", v(0, 10 + h, 0), v(W - 2, 4, D - 2), { material = "Slate", color = "RoofSlate" })
		box("Roof2", v(0, 13 + h, 0), v(W - 7, 3, D - 7), { material = "Slate", color = "RoofSlate" })
		box("Window", v(0, 4 + h, -D / 2 + 0.6), v(W / 2, 3, 0.4), decor({ material = "Neon", color = "WarmLight", transparency = 0.2 }))
		return
	end
	local wallMaterial = if b.kind == "Workshop" then "Brick" else "WoodPlanks"
	local wallColor = if b.kind == "Workshop" then "WeatheredStone" else "Timber"
	box("Base", v(0, 1.5, D / 2), v(W + 2, 3, D + 2), { material = "Cobblestone", color = "WeatheredStone" })
	box("Walls", v(0, 3 + h / 2, D / 2 + 1), v(W, h, D - 2), { material = wallMaterial, color = wallColor })
	box("Door", v(0, 6, -0.2), v(4, 6, 0.4), decor({ material = "Wood", color = "RootWood" }))
	box("WindowL", v(-W / 4, 3 + storey * 0.6, -0.2), v(3, 3, 0.3), decor({ material = "Neon", color = "WarmLight", transparency = 0.35 }))
	box("WindowR", v(W / 4, 3 + storey * 0.6, -0.2), v(3, 3, 0.3), decor({ material = "Neon", color = "WarmLight", transparency = 0.35 }))
	if floors >= 2 then
		box("Balcony", v(0, 3 + storey, -2), v(W - 4, 1, 4), { material = "WoodPlanks", color = "WeatheredWood" })
		box("BalconyRail", v(0, 4.5 + storey, -3.8), v(W - 4, 2, 0.4), { material = "Wood", color = "RootWood" })
	end
	-- Pitched roof: two tilted slabs meeting at a ridge along the building's width.
	local roofY = 3 + h
	local half = (D + 2) / 2
	local roofColor = if b.kind == "Workshop" then "RoofSlate" else "RoofClay"
	box("RoofFront", v(0, roofY + 2.5, D / 2 + 1 - half / 2), v(W + 3, 1, half * 1.18), { rot = { x = 30, y = yaw, z = 0 }, material = "Slate", color = roofColor })
	box("RoofBack", v(0, roofY + 2.5, D / 2 + 1 + half / 2), v(W + 3, 1, half * 1.18), { rot = { x = -30, y = yaw, z = 0 }, material = "Slate", color = roofColor })
	if b.kind == "Workshop" then
		box("Chimney", v(W / 3, roofY + 6, D / 2 + 3), v(3, 9, 3), { material = "Brick", color = "DarkStone" })
		-- Relic-powered equipment: a crystal core in an iron cradle.
		box("Cradle", v(-W / 2 - 2, 2.5, 3), v(3, 5, 3), { material = "Metal", color = "DarkStone" })
		box("Core", v(-W / 2 - 2, 6, 3), v(1.6, 2.4, 1.6), decor({ material = "Neon", color = "CrystalGlow" }))
	end
end

local function buildTown(plan, layout, world)
	local town = layout.Town
	local R0, R1, RB = world.OpeningRadius, world.TownOuterRadius, world.BoundaryRadius
	local step = 360 / town.RingSegments
	for i = 0, town.RingSegments - 1 do
		local angle = (i + 0.5) * step
		local width = 2 * R1 * math.sin(math.rad(step / 2)) + 3
		local center = polar((R0 + R1) / 2, angle, -2)
		local yaw = Geometry.yawFacing(-center.X, -center.Z)
		local groupName = `Town_Ring{math.floor(angle / 90)}`
		put(plan, groupName, {
			name = `Rim_{i}`,
			size = v(width, 4, R1 - R0),
			pos = center,
			rot = { x = 0, y = yaw, z = 0 },
			material = "Cobblestone",
			color = if Geometry.hash(i, 7) < 0.5 then "Cobble" else "WeatheredStone",
		})
		-- Parapet along the opening, with gaps at the gate and overlooks.
		if not inRanges(angle, town.ParapetGaps) then
			local edge = polar(R0 + 1, angle, town.ParapetHeight / 2)
			put(plan, groupName, {
				name = `Parapet_{i}`,
				size = v(2 * (R0 + 1) * math.sin(math.rad(step / 2)) + 0.6, town.ParapetHeight, 1.4),
				pos = edge,
				rot = { x = 0, y = yaw, z = 0 },
				material = "Limestone",
				color = "PaleStone",
			})
		end
		-- Outer hills and the boundary ridge (keeps players inside the world).
		local hillWidth = 2 * RB * math.sin(math.rad(step / 2)) + 4
		local hill = polar((R1 + RB) / 2, angle, -1.5)
		put(plan, "Town_Outskirts", {
			name = `Hill_{i}`,
			size = v(hillWidth, 3, RB - R1 + 2),
			pos = hill,
			rot = { x = 0, y = yaw, z = 0 },
			material = "Grass",
			color = if Geometry.hash(i, 3) < 0.5 then "Grass" else "Moss",
		})
		local ridgeHeight = 40 + 50 * Geometry.hash(i, 11)
		local ridge = polar(RB + 22, angle, ridgeHeight / 2 - 2)
		put(plan, "Town_Outskirts", {
			name = `Ridge_{i}`,
			size = v(hillWidth + 6, ridgeHeight, 44),
			pos = ridge,
			rot = { x = 0, y = yaw, z = 0 },
			material = "Rock",
			color = if Geometry.hash(i, 5) < 0.5 then "WeatheredStone" else "MossStone",
		})
		-- Vines hanging from under the rim edge.
		if i % math.max(1, math.floor(layout.Vines.UnderRimEvery / step)) == 0 then
			local length = 18 + 26 * Geometry.hash(i, 13)
			local vineAt = polar(ringRadius(layout, 0, angle) - 1.2, angle + 3, -4 - length / 2)
			put(plan, "Vegetation_Upper", decor({
				name = `RimVine_{i}`,
				size = v(1.4, length, 0.5),
				pos = vineAt,
				rot = { x = 0, y = yaw, z = 0 },
				material = "Grass",
				color = "Vine",
				shadow = false,
			}))
		end
	end

	-- Town zones: one box per segment over the walkable surface (shaft excluded), from just
	-- under the paving up to rooftops. Nothing below the rim surface counts as town.
	local zoneSegments = town.RingSegments
	for i = 0, zoneSegments - 1 do
		local angle = (i + 0.5) * (360 / zoneSegments)
		local width = 2 * RB * math.sin(math.rad(180 / zoneSegments)) + 2
		local center = polar((R0 + RB) / 2, angle, 28.5)
		put(plan, "Markers", {
			name = `TownZone_{i}`,
			size = v(width, 63, RB - R0),
			pos = center,
			rot = { x = 0, y = Geometry.yawFacing(-center.X, -center.Z), z = 0 },
			transparency = 1,
			collide = false,
			query = false,
			shadow = false,
			role = "Zone",
			tags = { "HB_TownZone" },
		})
	end

	-- Overlooks: cantilevered platforms over the shaft, with rails and struts.
	for _, overlook in town.Overlooks do
		local inner, outer = R0 - 30, R0 + 2
		local center = polar((inner + outer) / 2, overlook.angle, -1)
		local yaw = Geometry.yawFacing(-center.X, -center.Z)
		local groupName = "Town_Overlooks"
		put(plan, groupName, { name = overlook.name, size = v(24, 2, outer - inner), pos = center, rot = { x = 0, y = yaw, z = 0 }, material = "WoodPlanks", color = "WeatheredWood", extras = { signExtra(overlook.name, 6) } })
		local tip = polar(inner + 0.6, overlook.angle, 1.75)
		put(plan, groupName, { name = overlook.name .. "_RailFront", size = v(24, 3.5, 1), pos = tip, rot = { x = 0, y = yaw, z = 0 }, material = "Wood", color = "RootWood" })
		for side = -1, 1, 2 do
			local railCenter = add(center, rotate(v(side * 11.5, 2.75, 0), 0, yaw, 0))
			put(plan, groupName, { name = overlook.name .. "_RailSide", size = v(1, 3.5, outer - inner), pos = railCenter, rot = { x = 0, y = yaw, z = 0 }, material = "Wood", color = "RootWood" })
			local strut = add(polar(inner + 8, overlook.angle, -10), rotate(v(side * 9, 0, 0), 0, yaw, 0))
			put(plan, groupName, decor({ name = overlook.name .. "_Strut", size = v(1.5, 20, 1.5), pos = strut, rot = { x = -35, y = yaw, z = 0 }, material = "Wood", color = "RootWood" }))
		end
		put(plan, "Markers", {
			name = overlook.name .. "_Zone",
			size = v(24, 18, outer - inner),
			pos = polar((inner + outer) / 2, overlook.angle, 8),
			rot = { x = 0, y = yaw, z = 0 },
			transparency = 1,
			collide = false,
			query = false,
			shadow = false,
			role = "Zone",
			tags = { "HB_TownZone" },
		})
	end

	-- Lanterns along the edge (the town's lights).
	for index, angle in town.LanternAngles do
		local base = polar(R0 + 4, angle, 0)
		put(plan, "Town_Lanterns", { name = `LanternPost_{index}`, size = v(0.8, 9, 0.8), pos = add(base, v(0, 4.5, 0)), material = "Metal", color = "DarkStone" })
		put(plan, "Town_Lanterns", decor({ name = `Lantern_{index}`, size = v(1.4, 1.8, 1.4), pos = add(base, v(0, 9.6, 0)), material = "Neon", color = "WarmLight", extras = { lightExtra(1.2, 18, { 255, 200, 140 }) } }))
	end

	for _, b in town.Buildings do
		buildBuilding(plan, layout, b, `Town_Buildings{math.floor(b.angle / 90)}`)
	end

	-- Service district ---------------------------------------------------------------------
	local services = town.Services
	local district = "Town_ServiceDistrict"
	-- Spawn plaza
	local plaza = polar(town.SpawnPlaza.radius, town.SpawnPlaza.angle, 0)
	put(plan, district, { name = "Plaza", size = v(40, 0.4, 40), pos = add(plaza, v(0, 0.2, 0)), rot = { x = 0, y = Geometry.yawFacing(-plaza.X, -plaza.Z), z = 0 }, material = "Slate", color = "PaleStone" })
	put(plan, "Markers", {
		class = "SpawnLocation",
		name = "TownSpawn",
		size = v(10, 1, 10),
		pos = add(plaza, v(0, 0.9, 0)),
		rot = { x = 0, y = Geometry.yawFacing(-plaza.X, -plaza.Z), z = 0 },
		material = "Slate",
		color = "Cobble",
		role = "Marker",
		tags = { "HB_TownSpawn" },
		props = { Neutral = true, Duration = 0 },
	})
	put(plan, district, { name = "PlazaFountain", size = v(6, 3, 6), pos = add(plaza, v(-12, 1.5, 0)), material = "Limestone", color = "PaleStone", shape = "Cylinder", rot = { x = 0, y = 0, z = 90 } })
	put(plan, district, decor({ name = "PlazaFountainWater", size = v(1, 5, 5), pos = add(plaza, v(-12, 3.1, 0)), material = "Glass", color = "Water", transparency = 0.3, shape = "Cylinder", rot = { x = 0, y = 0, z = 90 } }))

	local function hall(def, kind: string)
		local b = { kind = kind, angle = def.angle, radius = def.radius, width = def.width, depth = def.depth, floors = if kind == "Lodge" then 2 else 1, name = def.name }
		buildBuilding(plan, layout, b, district)
		local front = polar(def.radius - def.depth / 2 - 6, def.angle, 0)
		local yaw = Geometry.yawFacing(-front.X, -front.Z)
		return front, yaw
	end
	-- Registry Hall and its terminal (registration, appraisal, activation desk).
	local regFront, regYaw = hall(services.Registry, "Lodge")
	put(plan, district, { name = "RegistrySign", size = v(10, 2, 0.5), pos = add(regFront, rotate(v(0, 13, 4.5), 0, regYaw, 0)), rot = { x = 0, y = regYaw, z = 0 }, material = "Wood", color = "RootWood", extras = { signExtra(services.Registry.name, 3) } })
	put(plan, "Markers", {
		name = "RegistryTerminal",
		size = v(4, 7, 2),
		pos = add(regFront, v(0, 3.5, 0)),
		rot = { x = 0, y = regYaw, z = 0 },
		material = "Metal",
		color = "Timber",
		role = "Marker",
		tags = { "HB_RegistrationTerminal" },
		extras = { signExtra("Registry Terminal", 5.5), lightExtra(0.8, 10, { 140, 230, 210 }) },
	})
	put(plan, district, decor({ name = "TerminalCrystal", size = v(1.2, 2, 1.2), pos = add(regFront, rotate(v(0, 7.8, 0), 0, regYaw, 0)), rot = { x = 0, y = regYaw, z = 0 }, material = "Neon", color = "CrystalGlow" }))
	-- Relic Workshop and its service bench.
	local shopFront, shopYaw = hall(services.Workshop, "Workshop")
	put(plan, "Markers", {
		name = "ServiceBench",
		size = v(5, 3, 3),
		pos = add(shopFront, v(0, 1.5, 0)),
		rot = { x = 0, y = shopYaw, z = 0 },
		material = "WoodPlanks",
		color = "Timber",
		role = "Marker",
		tags = { "HB_ServiceStation" },
		extras = { signExtra("Relic Service: repair and recharge", 4) },
	})
	put(plan, district, { name = "Anvil", size = v(2, 1, 1.2), pos = add(shopFront, v(0, 3.5, 0)), rot = { x = 0, y = shopYaw, z = 0 }, material = "Metal", color = "DarkStone" })
	-- Supply Depot and its station.
	local depotFront, depotYaw = hall(services.Depot, "Workshop")
	put(plan, "Markers", {
		name = "SupplyCrate",
		size = v(4, 3, 3),
		pos = add(depotFront, v(0, 1.5, 0)),
		rot = { x = 0, y = depotYaw, z = 0 },
		material = "WoodPlanks",
		color = "Cloth",
		role = "Marker",
		tags = { "HB_SupplyStation" },
		extras = { signExtra("Supply Station: free basic loadout", 4) },
	})
	for k = 1, 3 do
		put(plan, district, { name = `DepotCrate{k}`, size = v(3, 3, 3), pos = add(depotFront, rotate(v(5 + k * 0.5, 1.5 + (k - 1) * 3, 3), 0, depotYaw, 0)), rot = { x = 0, y = depotYaw + k * 7, z = 0 }, material = "WoodPlanks", color = "Timber" })
	end
	-- Relic-powered lift crane at the edge (decor; the route is on foot).
	local crane = polar(services.Crane.radius, services.Crane.angle, 0)
	local craneYaw = Geometry.yawFacing(-crane.X, -crane.Z)
	put(plan, district, { name = "CraneMast", size = v(2.5, 26, 2.5), pos = add(crane, v(0, 13, 0)), material = "Metal", color = "DarkStone" })
	put(plan, district, decor({ name = "CraneBoom", size = v(1.6, 1.6, 30), pos = add(crane, rotate(v(0, 25, -13), 0, craneYaw, 0)), rot = { x = 0, y = craneYaw, z = 0 }, material = "Wood", color = "RootWood" }))
	put(plan, district, decor({ name = "CraneCore", size = v(2.2, 3.4, 2.2), pos = add(crane, v(0, 6, 0)), material = "Neon", color = "CrystalGlow", extras = { lightExtra(0.8, 12, { 140, 230, 210 }) } }))
	put(plan, district, decor({ name = "CraneCage", size = v(5, 6, 5), pos = add(crane, rotate(v(0, 14, -26), 0, craneYaw, 0)), rot = { x = 0, y = craneYaw, z = 0 }, material = "Metal", color = "DarkStone", transparency = 0.5 }))
	-- Descent Gate arch and its landing over the shaft.
	local gate = services.Gate
	local gatePos = polar(gate.radius, gate.angle, 0)
	local gateYaw = Geometry.yawFacing(-gatePos.X, -gatePos.Z)
	for side = -1, 1, 2 do
		put(plan, district, { name = "GatePillar", size = v(3, 13, 3), pos = add(gatePos, rotate(v(side * 9, 6.5, 0), 0, gateYaw, 0)), rot = { x = 0, y = gateYaw, z = 0 }, material = "Limestone", color = "PaleStone" })
	end
	put(plan, district, { name = "GateLintel", size = v(22, 3, 3.4), pos = add(gatePos, v(0, 14.5, 0)), rot = { x = 0, y = gateYaw, z = 0 }, material = "Limestone", color = "PaleStone", extras = { signExtra(gate.name .. ": the way down", 4) } })
end

-- Route -----------------------------------------------------------------------------------------

local function addEdge(plan, a: string, b: string, kind: string, width: number, slope: number)
	table.insert(plan.route.edges, { a = a, b = b, kind = kind, width = width, slope = slope })
end

local function rail(plan, groupName: string, a, b, sideVector, offset: number, height: number, name: string)
	local shift = scale(sideVector, offset)
	local ra = add(add(a, shift), v(0, height, 0))
	local rb = add(add(b, shift), v(0, height, 0))
	local s = slabBetween(ra, rb, 0.8, height, 0.5)
	put(plan, groupName, { name = name, size = s.size, pos = s.pos, rot = s.rot, material = "Wood", color = "RootWood" })
end

-- A path from a to b: deck, plus a rail on the side facing `towardOpen` (and optionally
-- both sides for bridges). Registers a route edge.
local function path(plan, groupName: string, idA: string, a, idB: string, b, width: number, kind: string, opts)
	opts = opts or {}
	local s = slabBetween(a, b, width, 2, opts.overlap or 1.5)
	put(plan, groupName, {
		name = `{kind}_{idA}_{idB}`,
		size = s.size,
		pos = s.pos,
		rot = s.rot,
		material = opts.material or "Slate",
		color = opts.color or "WeatheredStone",
	})
	local d = sub(b, a)
	local side = rotate(v(1, 0, 0), 0, Geometry.yawFacing(d.X, d.Z), 0)
	if opts.railsBoth then
		rail(plan, groupName, a, b, side, width / 2 - 0.4, 3, `{kind}Rail_{idA}_{idB}_L`)
		rail(plan, groupName, a, b, side, -(width / 2 - 0.4), 3, `{kind}Rail_{idA}_{idB}_R`)
	elseif opts.towardOpen then
		local sign = if side.X * opts.towardOpen.X + side.Z * opts.towardOpen.Z >= 0 then 1 else -1
		rail(plan, groupName, a, b, side, sign * (width / 2 - 0.4), 3, `{kind}Rail_{idA}_{idB}`)
	end
	addEdge(plan, idA, idB, kind, width, s.slope)
end

local function landing(plan, groupName: string, id: string, at, size: number, yaw: number)
	put(plan, groupName, { name = `Landing_{id}`, size = v(size, 2, size), pos = add(at, v(0, -1, 0)), rot = { x = 0, y = yaw, z = 0 }, material = "Slate", color = "PaleStone" })
end

local function wallNode(layout, world, node)
	local radius
	if node.id == "Gate" then
		radius = world.OpeningRadius - 7
	else
		radius = clearRadius(layout, node.angle, node.depth) - (node.inset or layout.Route.Inset)
	end
	return polar(radius, node.angle, -node.depth)
end

local function buildWallRoute(plan, layout, world, nodes, groupName: string)
	local width = layout.Route.Width
	local previous, previousPos
	for _, node in nodes do
		local pos = plan.route.nodes[node.id] or wallNode(layout, world, node)
		plan.route.nodes[node.id] = pos
		local toCenter = scale(v(-pos.X, 0, -pos.Z), 1 / Geometry.flatLength(pos))
		landing(plan, groupName, node.id, pos, width + 4, Geometry.yawFacing(toCenter.X, toCenter.Z))
		if previous then
			if node.ladder then
				-- Switchback stair tower between two depths at the same spot.
				local top, bottom = previousPos, pos
				local drop = top.Y - bottom.Y
				local flights = math.max(2, math.ceil(drop / 9))
				local yaw = Geometry.yawFacing(toCenter.X, toCenter.Z)
				local tangent = rotate(v(1, 0, 0), 0, yaw, 0)
				local lanes = { scale(toCenter, -4), scale(toCenter, 8) }
				local current = top
				for f = 1, flights do
					local lane = lanes[(f - 1) % 2 + 1]
					local dir = if f % 2 == 1 then 1 else -1
					local startPoint = add(add(current, lane), scale(tangent, -dir * 8))
					local y = top.Y - drop * f / flights
					local endPoint = add(v(current.X, y, current.Z), add(lane, scale(tangent, dir * 8)))
					local s = slabBetween(startPoint, endPoint, 8, 2, 1)
					put(plan, groupName, { name = `Stair_{node.id}_{f}`, size = s.size, pos = s.pos, rot = s.rot, material = "WoodPlanks", color = "Timber" })
					addEdge(plan, `{node.id}_f{f - 1}`, `{node.id}_f{f}`, "Stairs", 8, s.slope)
					put(plan, groupName, { name = `StairLanding_{node.id}_{f}`, size = v(12, 2, 22), pos = add(add(v(current.X, y - 1, current.Z), scale(toCenter, 2)), scale(tangent, dir * 13)), rot = { x = 0, y = yaw, z = 0 }, material = "WoodPlanks", color = "WeatheredWood" })
					current = v(current.X, y, current.Z)
					current = add(current, scale(tangent, dir * 0)) -- turns happen at the landings
				end
				-- Scaffold posts and a parallel climbing truss (optional quick way).
				for corner = 1, 4 do
					local ox = if corner <= 2 then -12 else 12
					local oz = if corner % 2 == 1 then -6 else 10
					local postPos = add(add(top, scale(tangent, ox)), add(scale(toCenter, oz), v(0, -drop / 2, 0)))
					put(plan, groupName, decor({ name = `ScaffoldPost_{corner}`, size = v(1.4, drop + 4, 1.4), pos = postPos, material = "Wood", color = "RootWood" }))
				end
				put(plan, groupName, { class = "TrussPart", name = "ScaffoldTruss", size = v(2, drop, 2), pos = add(add(top, scale(tangent, -14)), add(scale(toCenter, 2), v(0, -drop / 2, 0))), material = "Metal", color = "DarkStone" })
				-- Graph: top -> flights -> bottom.
				addEdge(plan, previous.id, `{node.id}_f0`, "Landing", 8, 0)
				addEdge(plan, `{node.id}_f{flights}`, node.id, "Landing", 8, 0)
				plan.route.nodes[`{node.id}_f0`] = top
				plan.route.nodes[`{node.id}_f{flights}`] = pos
			else
				path(plan, groupName, previous.id, previousPos, node.id, pos, width, "Ramp", { towardOpen = toCenter })
			end
		end
		previous, previousPos = node, pos
	end
end

-- Elder Tree, its spiral walkway, the root bridge, and the camp bridge --------------------------

local function buildElderTree(plan, layout, world)
	local t = layout.ElderTree
	local center = polar(t.radius, t.angle, 0)
	local floorY = -world.FloorDepth
	local trunkHeight = world.FloorDepth - t.topDepth
	local groupName = "ElderTree"
	put(plan, groupName, {
		name = "ElderTrunk",
		shape = "Cylinder",
		size = v(trunkHeight + 6, t.trunkRadius * 2, t.trunkRadius * 2),
		pos = v(center.X, floorY + trunkHeight / 2, center.Z),
		rot = { x = 0, y = 0, z = 90 },
		material = "Wood",
		color = "RootWood",
	})
	-- Canopy: large leaf masses (non-colliding) above the root bridge.
	for i = 0, 6 do
		local angle = i * 51
		local r = if i == 0 then 0 else 22 + 10 * Geometry.hash(i, 21)
		local size = 34 + 16 * Geometry.hash(i, 22)
		local leafPos = add(polar(r, angle, -t.topDepth + 8 + 10 * Geometry.hash(i, 23)), v(center.X, 0, center.Z))
		put(plan, "ElderCanopy", decor({ name = `Canopy_{i}`, shape = "Ball", size = v(size, size, size), pos = leafPos, material = "LeafyGrass", color = if i % 2 == 0 then "Leaf" else "DeepLeaf", shadow = i == 0 }))
	end
	-- Roots flaring at the base.
	for i = 0, 5 do
		local angle = i * 60 + 15
		local rootPos = add(polar(t.trunkRadius + 6, angle, floorY + 3), v(center.X, 0, center.Z))
		put(plan, groupName, decor({ name = `Root_{i}`, size = v(5, 5, 22), pos = rootPos, rot = { x = -18, y = Geometry.yawFacing(math.cos(math.rad(angle)), math.sin(math.rad(angle))), z = 0 }, material = "Wood", color = "RootWood" }))
	end

	-- Spiral walkway nodes.
	local bridgeHead = plan.route.nodes.BridgeHead
	local phi0 = math.deg(math.atan2(bridgeHead.Z - center.Z, bridgeHead.X - center.X))
	local nodes = {}
	local depth, k = t.spiralTopDepth, 0
	while true do
		local phi = phi0 - k * t.stepDegrees
		local d = math.min(depth, world.FloorDepth)
		local pos = add(polar(t.spiralRadius, phi, -d), v(center.X, 0, center.Z))
		table.insert(nodes, { id = `Spiral{k}`, pos = pos, phi = phi, depth = d })
		if d >= world.FloorDepth then
			break
		end
		k += 1
		depth += t.stepDrop
	end
	-- The node nearest campDepth whose direction best faces the camp links to the camp.
	local campShelf
	for _, shelf in layout.Shelves do
		if shelf.camp then
			campShelf = shelf
		end
	end
	local campMid = (campShelf.from + campShelf.to) / 2
	local campPoint = polar(clearRadius(layout, campMid, campShelf.depth) - campShelf.inset + 3, campMid, 0)
	local campDir = math.deg(math.atan2(campPoint.Z - center.Z, campPoint.X - center.X))
	local link, bestScore = nil, -math.huge
	for _, n in nodes do
		if math.abs(n.depth - t.campDepth) <= 12 then
			local score = math.cos(math.rad(n.phi - campDir)) - math.abs(n.depth - t.campDepth) * 0.01
			if score > bestScore then
				link, bestScore = n, score
			end
		end
	end
	plan.info.campDepth = link.depth
	plan.info.campLinkNode = link.id

	local railSkip = { [nodes[1].id] = true, [link.id] = true }
	for i, n in nodes do
		plan.route.nodes[n.id] = n.pos
		if i > 1 then
			local a, b = nodes[i - 1], n
			local outward = scale(sub(v(b.pos.X, 0, b.pos.Z), v(center.X, 0, center.Z)), 1 / t.spiralRadius)
			local s = slabBetween(a.pos, b.pos, t.spiralWidth, 2, 2.5)
			put(plan, groupName, { name = `Walk_{a.id}_{b.id}`, size = s.size, pos = s.pos, rot = s.rot, material = "WoodPlanks", color = "WeatheredWood" })
			addEdge(plan, a.id, b.id, "Spiral", t.spiralWidth, s.slope)
			if not railSkip[a.id] and not railSkip[b.id] then
				local outwardA = scale(sub(v(a.pos.X, 0, a.pos.Z), v(center.X, 0, center.Z)), 1 / t.spiralRadius)
				local ra = add(add(a.pos, scale(outwardA, t.spiralWidth / 2 - 0.4)), v(0, 3, 0))
				local rb = add(add(b.pos, scale(outward, t.spiralWidth / 2 - 0.4)), v(0, 3, 0))
				local rs = slabBetween(ra, rb, 0.8, 3, 0.5)
				put(plan, groupName, { name = `WalkRail_{a.id}_{b.id}`, size = rs.size, pos = rs.pos, rot = rs.rot, material = "Wood", color = "RootWood" })
			end
		end
	end
	local bottom = nodes[#nodes]
	landing(plan, groupName, "ElderFloor", bottom.pos, 14, 0)
	addEdge(plan, bottom.id, "Floor", "Landing", 14, 0)

	-- Root bridge: bridge head on the wall to the top of the walkway.
	path(plan, "RootBridge", "BridgeHead", bridgeHead, nodes[1].id, nodes[1].pos, 8, "Bridge", { railsBoth = true, material = "WoodPlanks", color = "Timber" })
	local bridgeMid = Geometry.lerp(bridgeHead, nodes[1].pos, 0.5)
	for i = -1, 1 do
		local rootPos = add(bridgeMid, v(i * 14, -10, 0))
		put(plan, "RootBridge", decor({ name = `BridgeRoot_{i}`, size = v(4, 4, 40), pos = rootPos, rot = { x = 20, y = Geometry.yawFacing(bridgeHead.X - nodes[1].pos.X, bridgeHead.Z - nodes[1].pos.Z), z = 0 }, material = "Wood", color = "RootWood" }))
	end

	-- Camp bridge: the link node to the camp shelf's inner edge (same depth).
	local campEdge = v(campPoint.X, -link.depth, campPoint.Z)
	plan.route.nodes.CampEdge = campEdge
	path(plan, "Camp", link.id, link.pos, "CampEdge", campEdge, 8, "Bridge", { railsBoth = true, material = "WoodPlanks", color = "Timber" })
	return nodes
end

-- Shelves ---------------------------------------------------------------------------------------

local function buildShelf(plan, layout, shelf, depth: number)
	local groupName = "Shelf_" .. string.gsub(shelf.name, "%s", "")
	local steps = math.max(1, math.ceil((shelf.to - shelf.from) / 8))
	local slabs = {}
	for i = 0, steps - 1 do
		local a0 = shelf.from + (shelf.to - shelf.from) * i / steps
		local a1 = shelf.from + (shelf.to - shelf.from) * (i + 1) / steps
		local mid = (a0 + a1) / 2
		local wallR = clearRadius(layout, mid, depth)
		local inner, outer = wallR - shelf.inset, wallR + 10
		local width = 2 * outer * math.sin(math.rad((a1 - a0) / 2)) + 3
		local center = polar((inner + outer) / 2, mid, -depth - 3)
		local yaw = Geometry.yawFacing(-center.X, -center.Z)
		put(plan, groupName, { name = `{groupName}_{i}`, size = v(width, 6, outer - inner), pos = center, rot = { x = 0, y = yaw, z = 0 }, material = "Grass", color = if i % 2 == 0 then "Moss" else "Grass" })
		table.insert(slabs, { mid = mid, inner = inner, outer = outer, width = width, yaw = yaw })
		-- Vines under the shelf edge.
		local length = 14 + 18 * Geometry.hash(i, depth)
		put(plan, "Vegetation_Lower", decor({ name = `ShelfVine_{groupName}_{i}`, size = v(1.2, length, 0.5), pos = polar(inner + 1, mid, -depth - 6 - length / 2), rot = { x = 0, y = yaw, z = 0 }, material = "Grass", color = "Vine", shadow = false }))
	end
	return slabs, groupName
end

-- Floor -----------------------------------------------------------------------------------------

local function buildFloor(plan, layout, world)
	local floor = layout.Floor
	local floorY = -world.FloorDepth
	local tile = floor.TileSize
	local reach = 0
	for a = 0, 359, 15 do
		reach = math.max(reach, clearRadius(layout, a, world.FloorDepth))
	end
	reach += 12
	local pit = floor.Pit
	local pitCenter = polar(pit.radius, pit.angle, floorY)
	local function nearPit(x, z, margin)
		return math.sqrt((x - pitCenter.X) ^ 2 + (z - pitCenter.Z) ^ 2) <= margin
	end
	local count = math.ceil(reach / tile)
	for ix = -count, count do
		for iz = -count, count do
			local x, z = ix * tile, iz * tile
			if math.sqrt(x * x + z * z) > reach then
				continue
			end
			local groupName = if x >= 0 then "Floor_East" else "Floor_West"
			-- Tiles touching the pit are replaced by small tiles that leave a round hole.
			local touchesPit = nearPit(x, z, pit.size + tile * 0.75)
			if touchesPit then
				local sub = 4
				local small = tile / sub
				for sx = 0, sub - 1 do
					for sz = 0, sub - 1 do
						local cx = x - tile / 2 + small * (sx + 0.5)
						local cz = z - tile / 2 + small * (sz + 0.5)
						if not nearPit(cx, cz, pit.size + 1) then
							put(plan, "Floor_Pit", { name = `FloorBit_{ix}_{iz}_{sx}_{sz}`, size = v(small + 0.2, 8, small + 0.2), pos = v(cx, floorY - 4, cz), material = "Grass", color = "Moss" })
						end
					end
				end
			else
				put(plan, groupName, { name = `Floor_{ix}_{iz}`, size = v(tile + 0.4, 8, tile + 0.4), pos = v(x, floorY - 4, z), material = if Geometry.hash(ix, iz) < 0.5 then "Grass" else "LeafyGrass", color = if Geometry.hash(iz, ix) < 0.5 then "Grass" else "Moss" })
			end
		end
	end
	-- Pit lip stones (gaps let curious explorers look over the edge).
	for i = 0, 13 do
		if i % 4 ~= 3 then
			local angle = i * (360 / 14)
			local stonePos = add(polar(pit.size + 1.5, angle, floorY + 1.2), v(pitCenter.X, 0, pitCenter.Z))
			put(plan, "Floor_Pit", { name = `PitStone_{i}`, size = v(5, 2.4, 3), pos = stonePos, rot = { x = 0, y = Geometry.yawFacing(-math.cos(math.rad(angle)), -math.sin(math.rad(angle))), z = 0 }, material = "Rock", color = "DarkStone" })
		end
	end
	put(plan, "Floor_Pit", decor({ name = "PitSign", size = v(4, 3, 0.5), pos = add(pitCenter, v(pit.size + 6, 2, 0)), material = "Wood", color = "RootWood", extras = { signExtra("The Lower Dark (closed)", 3) } }))

	-- The Lower Dark: background only (no collision, no queries), with faint far lights.
	local rings = math.ceil((world.LowerDarkDepth - world.FloorDepth) / 30)
	for r = 0, rings - 1 do
		for s = 0, 7 do
			local angle = s * 45 + r * 10
			local radius = pit.size + 6 + 4 * Geometry.hash(r, s)
			local p = add(polar(radius + 6, angle, floorY - 20 - r * 30), v(pitCenter.X, 0, pitCenter.Z))
			put(plan, "LowerDark", background({ name = `DarkWall_{r}_{s}`, size = v(2 * radius * math.sin(math.rad(22.5)) + 6, 32, 12), pos = p, rot = { x = 0, y = Geometry.yawFacing(pitCenter.X - p.X, pitCenter.Z - p.Z), z = 0 }, material = "Basalt", color = "AbyssStone" }))
		end
	end
	for i = 0, 5 do
		local glint = add(polar(pit.size * 0.6 * Geometry.hash(i, 31), i * 60, floorY - 90 - 40 * Geometry.hash(i, 32)), v(pitCenter.X, 0, pitCenter.Z))
		put(plan, "LowerDark", background({ name = `FarLight_{i}`, size = v(0.6, 0.6, 0.6), pos = glint, material = "Neon", color = "CrystalGlow", shape = "Ball" }))
	end
	put(plan, "LowerDark", background({
		name = "DarkMist",
		size = v(pit.size * 1.6, 1, pit.size * 1.6),
		pos = add(pitCenter, v(0, -14, 0)),
		transparency = 1,
		extras = {
			{
				class = "ParticleEmitter",
				props = { Rate = 4, Lifetime = { nrange = { 8, 12 } }, Speed = { nrange = { 0.5, 1.5 } }, Size = { nseq = { 18, 30 } }, Transparency = { nseq = { 0.75, 1 } }, Color = { cseq = { 200, 220, 220 } }, LightEmission = 0, SpreadAngle = { v2 = { 180, 30 } } },
			},
		},
	}))

	-- Trees.
	for i, tree in floor.Trees do
		local base = polar(tree.radius, tree.angle, floorY)
		local r = tree.canopy * 0.3
		put(plan, "Vegetation_Floor", { name = `TreeTrunk_{i}`, shape = "Cylinder", size = v(tree.height, r * 2, r * 2), pos = add(base, v(0, tree.height / 2, 0)), rot = { x = 0, y = 0, z = 90 }, material = "Wood", color = "RootWood" })
		for c = 0, 2 do
			local size = tree.canopy * (1.4 - c * 0.25)
			local leaf = add(base, add(polar(tree.canopy * 0.4 * c, c * 120 + i * 30, tree.height - 2 + c * 3), v(0, 0, 0)))
			put(plan, "Vegetation_Floor", decor({ name = `TreeCanopy_{i}_{c}`, shape = "Ball", size = v(size, size * 0.8, size), pos = leaf, material = "LeafyGrass", color = if c == 1 then "LeafLight" else "Leaf", shadow = c == 0 }))
		end
	end

	-- Ruins.
	for i, ruin in floor.Ruins do
		local base = polar(ruin.radius, ruin.angle, floorY)
		local yaw = ruin.yaw or 0
		local group = "Ruins_Floor"
		if ruin.kind == "Pillar" then
			put(plan, group, { name = `Pillar_{i}`, size = v(4, 16, 4), pos = add(base, v(0, 8, 0)), rot = { x = 0, y = yaw + 10 * i, z = 0 }, material = "Limestone", color = "PaleStone" })
			put(plan, group, decor({ name = `PillarMoss_{i}`, size = v(4.4, 3, 4.4), pos = add(base, v(0, 14, 0)), rot = { x = 0, y = yaw + 10 * i, z = 0 }, material = "Grass", color = "Moss" }))
		elseif ruin.kind == "FallenPillar" then
			put(plan, group, { name = `Fallen_{i}`, size = v(4, 4, 18), pos = add(base, v(0, 2, 0)), rot = { x = 0, y = yaw, z = 0 }, material = "Limestone", color = "PaleStone" })
		elseif ruin.kind == "Arch" then
			for side = -1, 1, 2 do
				put(plan, group, { name = `ArchLeg_{i}`, size = v(3, 14, 3), pos = add(base, rotate(v(side * 7, 7, 0), 0, yaw, 0)), rot = { x = 0, y = yaw, z = 0 }, material = "Limestone", color = "PaleStone" })
			end
			put(plan, group, { name = `ArchTop_{i}`, size = v(17, 3, 3), pos = add(base, v(0, 15.5, 0)), rot = { x = 0, y = yaw, z = 0 }, material = "Limestone", color = "WeatheredStone" })
		elseif ruin.kind == "Wall" then
			put(plan, group, { name = `RuinWallL_{i}`, size = v(10, 9, 2.5), pos = add(base, rotate(v(-8, 4.5, 0), 0, yaw, 0)), rot = { x = 0, y = yaw, z = 0 }, material = "Brick", color = "WeatheredStone" })
			put(plan, group, { name = `RuinWallR_{i}`, size = v(8, 6, 2.5), pos = add(base, rotate(v(8, 3, 0), 0, yaw, 0)), rot = { x = 0, y = yaw, z = 0 }, material = "Brick", color = "WeatheredStone" })
		end
	end

	-- Creature dens (regular).
	for _, den in floor.Dens do
		put(plan, "Markers", {
			name = den.name,
			size = v(4, 0.2, 4),
			pos = polar(den.radius, den.angle, floorY + 0.1),
			material = "Neon",
			color = { 150, 60, 50 },
			transparency = 1,
			collide = false,
			query = false,
			shadow = false,
			role = "Marker",
			tags = { "HB_CreatureSpawn" },
			attrs = { Variant = "Regular" },
		})
	end

	-- Guardian clearing: standing stones, the den, and the cache by the wall.
	local g = floor.Guardian
	local den = polar(g.radius, g.angle, floorY)
	for i = 0, g.stones - 1 do
		if i ~= 0 then -- a gap facing the floor's center
			local angle = g.angle + 180 + i * (360 / g.stones)
			local stone = add(den, polar(g.stoneRing, angle, 4))
			put(plan, "Guardian", { name = `StandingStone_{i}`, size = v(3, 8 + 3 * Geometry.hash(i, 41), 2), pos = stone, rot = { x = 0, y = Geometry.yawFacing(den.X - stone.X, den.Z - stone.Z), z = 0 }, material = "Slate", color = "MossStone" })
		end
	end
	put(plan, "Markers", {
		name = "RootwardenDen",
		size = v(4, 0.2, 4),
		pos = add(den, v(0, 0.1, 0)),
		material = "Neon",
		color = { 150, 60, 50 },
		transparency = 1,
		collide = false,
		query = false,
		shadow = false,
		role = "Marker",
		tags = { "HB_CreatureSpawn" },
		attrs = { Variant = "Guardian", EncounterId = g.encounterId },
	})
	local cachePos = polar(g.cacheRadius, g.angle, floorY + 1)
	put(plan, "Markers", {
		name = "RootwardenCache",
		size = v(4, 2, 3),
		pos = cachePos,
		rot = { x = 0, y = Geometry.yawFacing(-cachePos.X, -cachePos.Z), z = 0 },
		material = "Slate",
		color = "WeatheredStone",
		role = "Marker",
		tags = { "HB_RelicCache" },
		attrs = { EncounterId = g.encounterId },
	})
	put(plan, "Guardian", decor({ name = "CacheGlyph", size = v(3, 0.2, 2), pos = add(cachePos, v(0, 1.1, 0)), material = "Neon", color = "RelicAccent", transparency = 0.4 }))

	-- Sky ledge (Windhook only): a raised shelf against the wall.
	local sky = floor.SkyLedge
	local wallR = clearRadius(layout, sky.angle, world.FloorDepth)
	local ledgeCenter = polar(wallR - sky.size / 2 + 4, sky.angle, floorY + sky.height / 2)
	put(plan, "Floor_SkyLedge", { name = "SkyLedge", size = v(sky.size, sky.height, sky.size + 8), pos = ledgeCenter, rot = { x = 0, y = Geometry.yawFacing(-ledgeCenter.X, -ledgeCenter.Z), z = 0 }, material = "Rock", color = "PaleStone" })
	plan.info.skyLedgeTop = add(ledgeCenter, v(0, sky.height / 2, -0))
	plan.info.floorY = floorY
	plan.info.pitCenter = pitCenter
	plan.info.pitSize = pit.size
end

-- Waterfalls ------------------------------------------------------------------------------------

local function buildWaterfalls(plan, layout, world)
	for i, fall in layout.Waterfalls do
		local height = fall.bottomDepth - fall.topDepth
		local midDepth = (fall.topDepth + fall.bottomDepth) / 2
		local r = clearRadius(layout, fall.angle, midDepth) + 3
		local center = polar(r, fall.angle, -midDepth)
		local yaw = Geometry.yawFacing(-center.X, -center.Z)
		put(plan, "Waterfalls", decor({ name = `Waterfall_{i}`, size = v(fall.width, height, 1.5), pos = center, rot = { x = 0, y = yaw, z = 0 }, material = "Glass", color = "Water", transparency = 0.35, shadow = false }))
		local bottom = polar(r - 4, fall.angle, -fall.bottomDepth + 1)
		put(plan, "Waterfalls", decor({
			name = `WaterfallMist_{i}`,
			size = v(fall.width, 1, 4),
			pos = bottom,
			transparency = 1,
			shadow = false,
			extras = {
				{ class = "ParticleEmitter", props = { Rate = 6, Lifetime = { nrange = { 2, 3 } }, Speed = { nrange = { 2, 4 } }, Size = { nseq = { 4, 10 } }, Transparency = { nseq = { 0.6, 1 } }, Color = { cseq = { 225, 240, 245 } }, SpreadAngle = { v2 = { 60, 60 } } } },
			},
		}))
		if fall.pool then
			local pool = polar(r - 14, fall.angle, -world.FloorDepth + 0.3)
			put(plan, "Waterfalls", decor({ name = `Pool_{i}`, shape = "Cylinder", size = v(0.6, 28, 28), pos = pool, rot = { x = 0, y = 0, z = 90 }, material = "Glass", color = "Water", transparency = 0.3, shadow = false }))
		end
	end
end

-- Assembly --------------------------------------------------------------------------------------

function Planner.plan(layout, world)
	local plan = newPlan()
	plan.info.killY = -world.KillDepth
	plan.info.lowerDarkY = -world.LowerDarkDepth

	buildWalls(plan, layout, world)
	buildTown(plan, layout, world)

	-- Upper route from the gate to the bridge head (with the Overhang Shelf on the way).
	buildWallRoute(plan, layout, world, layout.Route.Upper, "Route_Upper")
	local overhang
	for _, shelf in layout.Shelves do
		if not shelf.camp then
			local slabs, groupName = buildShelf(plan, layout, shelf, shelf.depth)
			if shelf.name == "Overhang Shelf" then
				overhang = { slabs = slabs, group = groupName }
			elseif shelf.name == "Lantern Ruins" then
				-- Ruins dressing and the two relic pedestals.
				local mid = slabs[math.ceil(#slabs / 2)]
				local ruinCenter = polar((mid.inner + mid.outer) / 2 - 4, mid.mid, -shelf.depth)
				for k = -1, 1, 2 do
					put(plan, groupName, { name = `RuinColumn_{k}`, size = v(3, 14, 3), pos = add(ruinCenter, rotate(v(k * 9, 7, 6), 0, mid.yaw, 0)), rot = { x = 0, y = mid.yaw, z = 0 }, material = "Limestone", color = "PaleStone" })
				end
				put(plan, groupName, decor({ name = "RuinLantern", size = v(1.4, 2, 1.4), pos = add(ruinCenter, rotate(v(0, 9, 8), 0, mid.yaw, 0)), material = "Neon", color = "WarmLight", extras = { lightExtra(0.9, 16, { 255, 200, 140 }) } }))
				for _, spawn in layout.RelicSpawns do
					if spawn.place == "LanternRuins" then
						put(plan, "Markers", { name = spawn.name, size = v(3, 2, 3), pos = add(ruinCenter, rotate(v(spawn.offset, 1, 0), 0, mid.yaw, 0)), rot = { x = 0, y = mid.yaw, z = 0 }, material = "Marble", color = "PaleStone", role = "Marker", tags = { "HB_RelicSpawn" } })
					end
				end
			end
		end
	end
	-- Overhang dressing: a small tree and boulders.
	if overhang then
		local s = overhang.slabs[2] or overhang.slabs[1]
		local p = polar((s.inner + s.outer) / 2, s.mid, -layout.Shelves[1].depth)
		put(plan, overhang.group, { name = "OverhangTreeTrunk", shape = "Cylinder", size = v(22, 3, 3), pos = add(p, v(0, 11, 0)), rot = { x = 0, y = 0, z = 90 }, material = "Wood", color = "RootWood" })
		put(plan, overhang.group, decor({ name = "OverhangTreeCanopy", shape = "Ball", size = v(18, 14, 18), pos = add(p, v(0, 24, 0)), material = "LeafyGrass", color = "LeafLight" }))
	end
	-- Lantern Ruins branch ledge from the bridge head.
	buildWallRoute(plan, layout, world, layout.Route.Branch, "Route_Branch")

	-- Elder Tree (alternate route to the floor), root bridge, and the camp link.
	buildElderTree(plan, layout, world)

	-- Mistfall Camp at the derived depth.
	local campDepth = plan.info.campDepth
	for _, shelf in layout.Shelves do
		if shelf.camp then
			local slabs, groupName = buildShelf(plan, layout, shelf, campDepth)
			for i, s in slabs do
				local center = polar((s.inner + s.outer) / 2, s.mid, -campDepth + 9)
				put(plan, "Markers", { name = `CampZone_{i}`, size = v(s.width, 20, s.outer - s.inner), pos = center, rot = { x = 0, y = s.yaw, z = 0 }, transparency = 1, collide = false, query = false, shadow = false, role = "Zone", tags = { "HB_CampZone" } })
			end
			local mid = slabs[math.ceil(#slabs / 2)]
			local campCenter = polar((mid.inner + mid.outer) / 2 - 6, mid.mid, -campDepth)
			put(plan, groupName, { name = "Campfire", size = v(3, 1, 3), pos = add(campCenter, v(0, 0.5, 0)), material = "Wood", color = "RootWood", extras = { { class = "Fire", props = { Size = 5, Heat = 6 } }, lightExtra(1.4, 22, { 255, 170, 100 }) } })
			for k = -1, 1, 2 do
				local tent = add(campCenter, rotate(v(k * 10, 3, 6), 0, mid.yaw, 0))
				put(plan, groupName, { class = "WedgePart", name = `Tent_{k}`, size = v(6, 6, 7), pos = tent, rot = { x = 0, y = mid.yaw + 90 * k, z = 0 }, material = "Fabric", color = "Cloth" })
			end
			put(plan, groupName, decor({ name = "CampSign", size = v(5, 3, 0.5), pos = add(campCenter, rotate(v(0, 3, -8), 0, mid.yaw, 0)), rot = { x = 0, y = mid.yaw, z = 0 }, material = "Wood", color = "RootWood", extras = { signExtra("Mistfall Camp: refuge (does not secure relics)", 3) } }))
		end
	end

	-- East route: camp exit -> scaffold -> floor landing (camp exit at the camp depth).
	local east = {}
	for _, node in layout.Route.East do
		local copy = table.clone(node)
		if copy.id == "CampExit" then
			copy.depth = campDepth
		end
		table.insert(east, copy)
	end
	buildWallRoute(plan, layout, world, east, "Route_East")
	addEdge(plan, "CampEdge", "CampExit", "Camp", 20, 0)
	addEdge(plan, "FloorLanding", "Floor", "Landing", 14, 0)

	buildFloor(plan, layout, world)
	buildWaterfalls(plan, layout, world)

	-- Relic spawns on the floor and the sky ledge.
	for _, spawn in layout.RelicSpawns do
		local pos
		if spawn.place == "Floor" then
			pos = polar(spawn.radius, spawn.angle, -world.FloorDepth + 1)
		elseif spawn.place == "SkyLedge" then
			pos = add(plan.info.skyLedgeTop, v(0, 1, 0))
		end
		if pos then
			put(plan, "Markers", { name = spawn.name, size = v(3, 2, 3), pos = pos, material = "Marble", color = "PaleStone", role = "Marker", tags = { "HB_RelicSpawn" } })
		end
	end

	-- Named regions for the HUD.
	for _, region in layout.Regions do
		local center = polar(region.radius, region.angle, -region.depth + region.height / 2 - 2)
		put(plan, "Markers", {
			name = "Region_" .. string.gsub(region.name, "[^%w]", ""),
			size = v(1, 1, 1),
			pos = center,
			transparency = 1,
			collide = false,
			query = false,
			shadow = false,
			role = "Marker",
			tags = { "HB_Region" },
			attrs = { RegionName = region.name, Radius = region.size, Height = region.height, Priority = region.priority },
		})
	end

	-- Floor node for the route graph (any point on the floor counts).
	plan.route.nodes.Floor = v(0, -world.FloorDepth, 0)
	return plan
end

-- Counts parts per role (for the installer report and tests).
function Planner.stats(plan)
	local stats = { parts = 0, byRole = {}, lights = 0, groups = #plan.groupOrder }
	for _, name in plan.groupOrder do
		for _, spec in plan.groups[name].parts do
			stats.parts += 1
			stats.byRole[spec.role] = (stats.byRole[spec.role] or 0) + 1
			for _, extra in spec.extras or {} do
				if extra.class == "PointLight" then
					stats.lights += 1
				end
			end
		end
	end
	return stats
end

return Planner
