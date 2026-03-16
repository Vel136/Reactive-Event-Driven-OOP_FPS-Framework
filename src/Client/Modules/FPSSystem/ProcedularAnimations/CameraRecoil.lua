--!native
--!optimize 2
--[[
	Camera Recoil Module
	Handles camera kick/recoil using spring physics
	Version 2.0
--]]
local module = {}

-- Pre-cache
local Random = math.random
local Rad = math.rad
local Angles = CFrame.Angles
local V3 = Vector3.new

-- Dependencies
local SpringMod = require(game.ReplicatedStorage.Shared.Modules.Utilities.Spring)
local Camera = workspace.CurrentCamera

-- Configuration
local DefaultRecoil = {
	Pitch = {10, 20},      -- Vertical kick (up/down)
	Yaw = {-5, 5},         -- Horizontal spread (left/right)
	Roll = {-3, 3}         -- Camera tilt
}

-- Default Configuration
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

export type Configuration = {
	SpringDamping : number,
	SpringSpeed : number,
	
	Pitch : {number},
	Yaw : {number},
	Roll : {number}
	
}
local CameraRecoil = {
	CameraSpring = CameraSpring,
	
	Pitch = DefaultRecoil.Pitch,
	Roll = DefaultRecoil.Roll,
	Yaw = DefaultRecoil.Yaw
}

function CameraRecoil.Update(self : CameraRecoil)
	-- Apply recoil offset to current camera
	Camera.CFrame = Camera.CFrame * Angles(
		CameraSpring.p.X,
		CameraSpring.p.Y,
		CameraSpring.p.Z
	)
end
function CameraRecoil.SetConfig(self : CameraRecoil, Configuration : Configuration)
	self.CameraSpring.d = Configuration.SpringDamping or self.CameraSpring.d
	self.CameraSpring.s = Configuration.SpringSpeed or self.CameraSpring.s

	self.Pitch = Configuration.Pitch or self.Pitch
	self.Yaw = Configuration.Yaw or self.Yaw
	self.Roll = Configuration.Roll or self.Roll
	
	return true
end
function CameraRecoil.Reset(self : CameraRecoil)
	self.CameraSpring.p = V3()
	self.CameraSpring.v = V3()
end

function CameraRecoil.Apply(self : CameraRecoil)
	local pitchRecoil = RandomInRange(self.Pitch)
	local yawRecoil = RandomInRange(self.Yaw)
	local rollRecoil = RandomInRange(self.Roll)
	
	self.CameraSpring:accelerate(V3(
		Rad(pitchRecoil),
		Rad(yawRecoil),
		Rad(rollRecoil)
		))
end

function module.new(Configuration : Configuration) : CameraRecoil
	local CameraRecoil = setmetatable({},{__index = CameraRecoil})
	
	CameraRecoil.CameraSpring.d = Configuration and Configuration.SpringDamping or SpringDamping
	CameraRecoil.CameraSpring.s = Configuration and Configuration.SpringSpeed or SpringSpeed
	
	CameraRecoil.Pitch = Configuration and Configuration.Pitch or CameraRecoil.Pitch
	CameraRecoil.Yaw = Configuration and Configuration.Yaw or CameraRecoil.Yaw
	CameraRecoil.Roll = Configuration and Configuration.Roll or CameraRecoil.Roll
	return CameraRecoil
end

export type CameraRecoil = typeof(setmetatable({},{__index = CameraRecoil}))

return module