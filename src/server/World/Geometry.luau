--[[
	Pure geometry for world planning and validation. Vectors are plain { X, Y, Z } tables,
	so this runs in Studio, on the server, and under Lune without Roblox datatypes.

	Rotations follow Roblox CFrame.fromOrientation(rx, ry, rz) (= fromEulerAnglesYXZ):
	the rotation matrix is Ry * Rx * Rz. Angles in this module are in degrees unless named
	"...Rad". A part's front is -Z (LookVector), as in Roblox.

	World polar coordinates: angle 0 points to +X, 90 to +Z. y is height relative to the
	world origin (the rim surface), so depth d is y = -d.
]]

local Geometry = {}

function Geometry.v(x: number, y: number, z: number)
	return { X = x, Y = y, Z = z }
end

function Geometry.add(a, b)
	return { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }
end

function Geometry.sub(a, b)
	return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }
end

function Geometry.scale(a, s: number)
	return { X = a.X * s, Y = a.Y * s, Z = a.Z * s }
end

function Geometry.length(a): number
	return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
end

function Geometry.flatLength(a): number
	return math.sqrt(a.X * a.X + a.Z * a.Z)
end

function Geometry.lerp(a, b, t: number)
	return { X = a.X + (b.X - a.X) * t, Y = a.Y + (b.Y - a.Y) * t, Z = a.Z + (b.Z - a.Z) * t }
end

-- Point at polar (radius, angle in degrees) and height y.
function Geometry.polar(radius: number, angleDeg: number, y: number)
	local a = math.rad(angleDeg)
	return { X = radius * math.cos(a), Y = y, Z = radius * math.sin(a) }
end

-- Polar angle (degrees, 0..360) and radius of a point.
function Geometry.toPolar(p): (number, number)
	local angle = math.deg(math.atan2(p.Z, p.X)) % 360
	return angle, math.sqrt(p.X * p.X + p.Z * p.Z)
end

-- Yaw (degrees) that makes a part's front (-Z) point along the horizontal (dx, dz).
function Geometry.yawFacing(dx: number, dz: number): number
	return math.deg(math.atan2(-dx, -dz))
end

-- Rotates v by fromOrientation(rx, ry, rz) in degrees: Ry * Rx * Rz * v.
function Geometry.rotate(v, rxDeg: number, ryDeg: number, rzDeg: number)
	local rx, ry, rz = math.rad(rxDeg), math.rad(ryDeg), math.rad(rzDeg)
	-- Rz
	local x1 = v.X * math.cos(rz) - v.Y * math.sin(rz)
	local y1 = v.X * math.sin(rz) + v.Y * math.cos(rz)
	local z1 = v.Z
	-- Rx
	local x2 = x1
	local y2 = y1 * math.cos(rx) - z1 * math.sin(rx)
	local z2 = y1 * math.sin(rx) + z1 * math.cos(rx)
	-- Ry
	local x3 = x2 * math.cos(ry) + z2 * math.sin(ry)
	local y3 = y2
	local z3 = -x2 * math.sin(ry) + z2 * math.cos(ry)
	return { X = x3, Y = y3, Z = z3 }
end

-- Inverse of rotate: Rz^-1 * Rx^-1 * Ry^-1 * v.
function Geometry.unrotate(v, rxDeg: number, ryDeg: number, rzDeg: number)
	local rx, ry, rz = math.rad(-rxDeg), math.rad(-ryDeg), math.rad(-rzDeg)
	-- Ry^-1
	local x1 = v.X * math.cos(ry) + v.Z * math.sin(ry)
	local y1 = v.Y
	local z1 = -v.X * math.sin(ry) + v.Z * math.cos(ry)
	-- Rx^-1
	local x2 = x1
	local y2 = y1 * math.cos(rx) - z1 * math.sin(rx)
	local z2 = y1 * math.sin(rx) + z1 * math.cos(rx)
	-- Rz^-1
	local x3 = x2 * math.cos(rz) - y2 * math.sin(rz)
	local y3 = x2 * math.sin(rz) + y2 * math.cos(rz)
	return { X = x3, Y = y3, Z = z2 }
end

-- True if point p is inside an oriented box (center, size, rotation in degrees).
function Geometry.insideBox(p, center, size, rot): boolean
	local localP = Geometry.unrotate(Geometry.sub(p, center), rot.x or 0, rot.y or 0, rot.z or 0)
	return math.abs(localP.X) <= size.X / 2 and math.abs(localP.Y) <= size.Y / 2 and math.abs(localP.Z) <= size.Z / 2
end

-- Small deterministic hash in [0, 1) from integers, for repeatable variation (no RNG).
function Geometry.hash(a: number, b: number?): number
	local n = math.sin((a * 12.9898 + (b or 0) * 78.233)) * 43758.5453
	return n - math.floor(n)
end

return Geometry
