local module = {}

module.HitscanSolver = require(script.Solvers.HitscanSolver)
module.ProjectileSolver = require( script.Solvers.ProjectileSolver)
local BulletContext = require(script.BulletContext)

function module.LineIntersectsSphere(startPos, endPos, sphereCenter, sphereRadius)
	local d = endPos - startPos
	local f = startPos - sphereCenter

	local a = d:Dot(d)
	local b = 2 * f:Dot(d)
	local c = f:Dot(f) - sphereRadius^2

	local discriminant = b^2 - 4*a*c
	if discriminant < 0 then return false end

	discriminant = math.sqrt(discriminant)
	local t1 = (-b - discriminant) / (2*a)
	local t2 = (-b + discriminant) / (2*a)

	return (t1 >= 0 and t1 <= 1) or (t2 >= 0 and t2 <= 1)
end

function module.DistancePointToSegment(A, B, C)
	local AB = B - A
	local AC = C - A

	local abLenSq = AB:Dot(AB)
	if abLenSq == 0 then
		return (C - A).Magnitude, A
	end

	local t = AC:Dot(AB) / abLenSq
	t = math.clamp(t, 0, 1)

	local closestPoint = A + AB * t
	local distance = (C - closestPoint).Magnitude

	return distance, closestPoint
end


function module.newBullet(config)
	return BulletContext.new(config)
end
return module
