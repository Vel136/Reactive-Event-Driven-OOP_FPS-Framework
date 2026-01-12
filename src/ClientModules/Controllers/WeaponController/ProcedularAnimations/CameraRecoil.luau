--!native
--!optimize 2
--[[
	Camera Recoil Module
	Handles camera kick/recoil using spring physics
--]]
local CameraRecoil = {}

-- Pre-cache
local Random = math.random
local Rad = math.rad
local Angles = CFrame.Angles
local V3 = Vector3.new

-- Dependencies
local SpringMod = require(game.ReplicatedStorage.SharedModules.Utilities.Spring)
local Camera = workspace.CurrentCamera

-- Configuration
local DefaultRecoil = {
	Pitch = {10, 20},      -- Vertical kick (up/down)
	Yaw = {-5, 5},         -- Horizontal spread (left/right)
	Roll = {-3, 3}         -- Camera tilt
}

local SpringDamping = 0.5
local SpringSpeed = 25

-- State
local CameraSpring = SpringMod.new(V3())
CameraSpring.d = SpringDamping
CameraSpring.s = SpringSpeed

-- Generate random value in range
local function RandomInRange(range)
	return range[1] + Random() * (range[2] - range[1])
end

function CameraRecoil.ApplyRecoil(recoilData)
	local data = recoilData or DefaultRecoil
	-- Calculate recoil values
	local pitchRecoil = RandomInRange(data.Pitch)
	local yawRecoil = RandomInRange(data.Yaw)
	local rollRecoil = RandomInRange(data.Roll)
	-- Convert to radians and apply impulse
	CameraSpring:accelerate(V3(
		Rad(pitchRecoil),
		Rad(yawRecoil),
		Rad(rollRecoil)
		))
end

function CameraRecoil.Update(deltaTime)
	if not deltaTime or deltaTime <= 0 then
		return
	end
	-- Apply recoil offset to current camera
	Camera.CFrame = Camera.CFrame * Angles(
		CameraSpring.p.X,
		CameraSpring.p.Y,
		CameraSpring.p.Z
	)
end

function CameraRecoil.Reset()
	CameraSpring.p = V3()
	CameraSpring.v = V3()
end

function CameraRecoil.Cleanup()
	CameraSpring.p = V3()
	CameraSpring.v = V3()
end
return CameraRecoil