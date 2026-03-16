local Spring = {}

type Vector3 = {
	X: number,
	Y: number,
	Z: number,
	magnitude: number
}

type SpringValue = number | Vector3

export type Spring = {
	accelerate: (self: Spring, acceleration: SpringValue) -> (),
	value: SpringValue,
	position: SpringValue,
	p: SpringValue,
	velocity: SpringValue,
	v: SpringValue,
	acceleration: SpringValue,
	a: SpringValue,
	target: SpringValue,
	t: SpringValue,
	damper: number,
	d: number,
	speed: number,
	s: number,
	magnitude: number?,
	m: number?,
}

function Spring.new(Initial: SpringValue?): Spring
	local t0 = tick()
	local p0: SpringValue = Initial or 0
	local v0: SpringValue = if Initial then 0 * Initial else 0
	local t: SpringValue = Initial or 0
	local d: number = 1
	local s: number = 1

	local function positionVelocity(Tick: number): (SpringValue, SpringValue)
		local x = Tick - t0
		local c0 = p0 - t
		if s == 0 then
			return p0, if typeof(p0) == "number" then 0 else 0 * (p0 :: Vector3)
		elseif d < 1 then
			local c = math.sqrt(1 - d ^ 2)
			local c1 = (v0 / s + d * c0) / c
			local co = math.cos(c * s * x)
			local si = math.sin(c * s * x)
			local e = math.exp(d * s * x)
			return t + (c0 * co + c1 * si) / e,
			s * ((c * c1 - d * c0) * co - (c * c0 + d * c1) * si) / e
		else
			local c1 = v0 / s + c0
			local e = math.exp(s * x)
			return t + (c0 + c1 * s * x) / e,
			s * (c1 - c0 - c1 * s * x) / e
		end
	end

	return setmetatable(
		{
			accelerate = function(_: Spring, acceleration: SpringValue)
				local T = tick()
				local p, v = positionVelocity(T)
				p0 = p
				v0 = v + acceleration
				t0 = T
			end,
		} :: any,
		{
			__index = function(_: any, index: string): any
				if index == "value" or index == "position" or index == "p" then
					local p, v = positionVelocity(tick())
					return p
				elseif index == "velocity" or index == "v" then
					local p, v = positionVelocity(tick())
					return v
				elseif index == "acceleration" or index == "a" then
					local x = tick() - t0
					local c0 = p0 - t
					if s == 0 then
						return if typeof(p0) == "number" then 0 else 0 * (p0 :: Vector3)
					elseif d < 1 then
						local c = math.sqrt(1 - d ^ 2)
						local c1 = (v0 / s + d * c0) / c
						local cs = (c0 * d ^ 2 - 2 * c * d * c1 - c0 * c ^ 2) * math.cos(c * s * x)
						local sn = (c1 * d ^ 2 + 2 * c * d * c0 - c1 * c ^ 2) * math.sin(c * s * x)
						return s ^ 2 * (cs + sn) / math.exp(d * s * x)
					else
						local c1 = v0 / s + c0
						return s ^ 2 * (c0 - 2 * c1 + c1 * s * x) / math.exp(s * x)
					end
				elseif index == "target" or index == "t" then
					return t
				elseif index == "damper" or index == "d" then
					return d
				elseif index == "speed" or index == "s" then
					return s
				elseif index == "magnitude" or index == "m" then
					local p, v = positionVelocity(tick())
					if typeof(p) == "Vector3" then
						return (p :: Vector3).magnitude
					else
						return nil
					end
				else
					error(index .. " is not a valid member of spring", 0)
				end
			end,

			__newindex = function(_: any, index: string, value: any)
				local T = tick()
				if index == "value" or index == "position" or index == "p" then
					local p, v = positionVelocity(T)
					p0, v0 = value, v
				elseif index == "velocity" or index == "v" then
					local p, v = positionVelocity(T)
					p0, v0 = p, value
				elseif index == "acceleration" or index == "a" then
					local p, v = positionVelocity(T)
					p0, v0 = p, v + value
				elseif index == "target" or index == "t" then
					p0, v0 = positionVelocity(T)
					t = value
				elseif index == "damper" or index == "d" then
					p0, v0 = positionVelocity(T)
					d = if value < 0 then 0 elseif value < 1 then value else 1
				elseif index == "speed" or index == "s" then
					p0, v0 = positionVelocity(T)
					s = if value < 0 then 0 else value
				else
					error(index .. " is not a valid member of spring", 0)
				end
				t0 = T
			end,
		}
	) :: Spring
end

return Spring