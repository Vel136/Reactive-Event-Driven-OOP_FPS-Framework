local UserInputService = game:GetService("UserInputService")
local module = {}
local DefaultConfiguration = {
	-- Controls how much the camera position moves per pixel of mouse movement
	-- Higher values = less sway, Lower values = more sway
	-- Default: 50 (smooth, subtle positional movement)
	DivisorCam = 50,
	-- Controls how much the camera rotates per pixel of mouse movement
	-- Higher values = less rotation, Lower values = more rotation
	-- Default: 150 (very subtle rotational sway)
	DivisorRot = 150,
	-- Maximum distance (in studs) the camera can sway in any direction
	-- Prevents extreme camera displacement from fast mouse movements
	-- Default: 0.3 studs (keeps sway subtle and controlled)
	MouseSwayClamp = .3,
	-- Maximum rotation angle (in radians) for camera sway
	-- Prevents excessive tilting from fast mouse movements
	-- Default: 0.03 radians (~1.7 degrees)
	RotationSwayClamp = .03,
	-- Speed at which the sway smoothly transitions (0-1 range)
	-- Higher values = snappier response, Lower values = smoother/slower
	-- Default: 0.1 (smooth, natural feeling movement)
	SwaySpeed = .1,
	SwayCam = nil,
	SwayRot = nil,
}

local MouseSway = {}
function MouseSway.Update(self : MouseSway)
	local MouseDelta = UserInputService:GetMouseDelta()

	local swayCamX = math.clamp(
		MouseDelta.X / self.DivisorCam,
		-self.MouseSwayClamp,
		self.MouseSwayClamp
	)
	local swayCamY = math.clamp(
		MouseDelta.Y / self.DivisorCam,
		-self.MouseSwayClamp,
		self.MouseSwayClamp
	)
	self.SwayCam = self.SwayCam:Lerp(
		CFrame.new(-swayCamX, swayCamY, 0),
		self.SwaySpeed
	)
	-- Rotation sway
	local swayRotX = math.clamp(
		MouseDelta.X / self.DivisorRot,
		-self.RotationSwayClamp,
		self.RotationSwayClamp
	)
	local swayRotY = math.clamp(
		MouseDelta.Y / self.DivisorRot,
		-self.RotationSwayClamp,
		self.RotationSwayClamp
	)
	self.SwayRot = self.SwayRot:Lerp(
		CFrame.Angles(-swayRotY, -swayRotX, 0),
		self.SwaySpeed
	)
end
function MouseSway.Reset(self : MouseSway)
	self.SwayCam = CFrame.new()
	self.SwayRot = CFrame.new()
end
function MouseSway.GetRotationCFrame(self : MouseSway)
	return self.SwayRot
end
function MouseSway.GetPositionCFrame(self : MouseSway)
	return self.SwayCam
end
function MouseSway.GetCFrame(self : MouseSway)
	return self.SwayRot * self.SwayCam
end
function module.new(Configuration : Configuration) : MouseSway
	local MouseSway = setmetatable({}, {__index = MouseSway}) :: MouseSway
	MouseSway.SwayCam = CFrame.new()
	MouseSway.SwayRot = CFrame.new()

	MouseSway.DivisorCam = Configuration and Configuration.DivisorCam or DefaultConfiguration.DivisorCam
	MouseSway.DivisorRot = Configuration and Configuration.DivisorRot or DefaultConfiguration.DivisorRot

	MouseSway.MouseSwayClamp = Configuration and Configuration.MouseSwayClamp or DefaultConfiguration.MouseSwayClamp
	MouseSway.RotationSwayClamp = Configuration and Configuration.RotationSwayClamp or DefaultConfiguration.RotationSwayClamp

	MouseSway.SwaySpeed = Configuration and Configuration.SwaySpeed or DefaultConfiguration.SwaySpeed
	return MouseSway
end
export type Configuration = typeof(DefaultConfiguration)
export type MouseSway = typeof(setmetatable({} :: Configuration, {__index = MouseSway}))
return module