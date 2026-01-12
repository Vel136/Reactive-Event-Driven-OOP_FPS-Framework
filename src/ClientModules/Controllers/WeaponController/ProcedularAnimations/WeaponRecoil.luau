--[[
	GunKick Module
	Handles procedural gun recoil with automatic recovery (Frame-rate independent)
	Call Kick() from external scripts to trigger recoil
--]]

local GunKick = {}

-- Default Configuration
local Config = {
	-- Animation speeds (per-second rates)
	KickIntensity = 1.0,
	RecoverySpeed = 8.0,
	RotationRecoverySpeed = 6.0,
	KickSnapSpeed = 25.0,

	-- Rotation ranges (radians)
	Rotation = {
		X = {Min = math.rad(2), Max = math.rad(5)}, -- Vertical
		Y = {Min = math.rad(-1), Max = math.rad(1)}, -- Horizontal
		Z = {Min = math.rad(-0.5), Max = math.rad(0.5)}, -- Roll
	},

	-- Position ranges (studs)
	Position = {
		X = {Min = -0.05, Max = 0.05},
		Y = {Min = -0.03, Max = 0.03},
		Z = {Min = 0.1, Max = 0.2}, -- Backward push
	},

	-- Safety limits to prevent extreme rotation/position
	MaxRotation = {
		X = math.rad(10), -- Max 45 degrees upward
		Y = math.rad(20), -- Max 20 degrees left/right
		Z = math.rad(10), -- Max 10 degrees roll
	},

	MaxPosition = {
		X = 0.5, -- Max half stud left/right
		Y = 0.5, -- Max half stud up/down
		Z = 1.0, -- Max 1 stud backward
	},
}

-- State Variables
local CurrentRotationKick = CFrame.new()
local CurrentPositionKick = CFrame.new()
local TargetRotationKick = CFrame.new()
local TargetPositionKick = CFrame.new()

local IsKicking = false
local KickStartTime = 0
local LastKickTime = 0

-- Random number generator
local Random = Random.new()

--[[
	Generates a random number between min and max
	@param Min number
	@param Max number
	@return number
]]
local function RandomRange(Min, Max)
	return Min + Random:NextNumber() * (Max - Min)
end

--[[
	Clamps a value between min and max
	@param Value number
	@param Min number
	@param Max number
	@return number
]]
local function Clamp(Value, Min, Max)
	return math.min(math.max(Value, Min), Max)
end

--[[
	Extracts euler angles from a CFrame (X, Y, Z rotation in radians)
	@param CF CFrame
	@return number, number, number - X, Y, Z angles
]]
local function GetAnglesFromCFrame(CF)
	local X, Y, Z = CF:ToEulerAnglesXYZ()
	return X, Y, Z
end

--[[
	Clamps a CFrame's rotation to maximum allowed values
	@param CF CFrame
	@return CFrame - Clamped CFrame
]]
local function ClampRotation(CF)
	local X, Y, Z = GetAnglesFromCFrame(CF)

	-- Clamp each axis
	X = Clamp(X, -Config.MaxRotation.X, Config.MaxRotation.X)
	Y = Clamp(Y, -Config.MaxRotation.Y, Config.MaxRotation.Y)
	Z = Clamp(Z, -Config.MaxRotation.Z, Config.MaxRotation.Z)

	return CFrame.Angles(X, Y, Z)
end

--[[
	Clamps a CFrame's position to maximum allowed values
	@param CF CFrame
	@return CFrame - Clamped CFrame
]]
local function ClampPosition(CF)
	local Pos = CF.Position

	local X = Clamp(Pos.X, -Config.MaxPosition.X, Config.MaxPosition.X)
	local Y = Clamp(Pos.Y, -Config.MaxPosition.Y, Config.MaxPosition.Y)
	local Z = Clamp(Pos.Z, -Config.MaxPosition.Z, Config.MaxPosition.Z)

	return CFrame.new(X, Y, Z)
end

--[[
	Triggers a gun kick with random recoil
	Call this function when the gun fires
	@param Intensity number - Optional intensity multiplier (default 1.0)
]]
function GunKick.Kick(Intensity)
	Intensity = Intensity or 1.0
	local FinalIntensity = Config.KickIntensity * Intensity

	-- Generate random rotation kick
	local RotX = RandomRange(Config.Rotation.X.Min, Config.Rotation.X.Max) * FinalIntensity
	local RotY = RandomRange(Config.Rotation.Y.Min, Config.Rotation.Y.Max) * FinalIntensity
	local RotZ = RandomRange(Config.Rotation.Z.Min, Config.Rotation.Z.Max) * FinalIntensity

	-- Generate random position kick
	local PosX = RandomRange(Config.Position.X.Min, Config.Position.X.Max) * FinalIntensity
	local PosY = RandomRange(Config.Position.Y.Min, Config.Position.Y.Max) * FinalIntensity
	local PosZ = RandomRange(Config.Position.Z.Min, Config.Position.Z.Max) * FinalIntensity

	-- Add to current kick (allows for kick stacking during rapid fire)
	TargetRotationKick = TargetRotationKick * CFrame.Angles(RotX, RotY, RotZ)
	TargetPositionKick = TargetPositionKick * CFrame.new(PosX, PosY, PosZ)

	-- Apply safety clamps to prevent extreme rotations
	TargetRotationKick = ClampRotation(TargetRotationKick)
	TargetPositionKick = ClampPosition(TargetPositionKick)

	IsKicking = true
	KickStartTime = os.clock()
	LastKickTime = os.clock()
end

--[[
	Updates the gun kick animation
	Call this every frame (RenderStepped)
	@param DeltaTime number - Time since last frame
]]
function GunKick.Update(DeltaTime)
	local TimeSinceLastKick = os.clock() - LastKickTime

	-- If enough time has passed since last kick, start recovering
	if TimeSinceLastKick > 0.1 then
		-- Calculate frame-rate independent lerp alphas
		local RecoveryAlpha = 1 - math.exp(-Config.RecoverySpeed * DeltaTime)
		local RotationRecoveryAlpha = 1 - math.exp(-Config.RotationRecoverySpeed * DeltaTime)

		-- Smoothly recover rotation to neutral
		CurrentRotationKick = CurrentRotationKick:Lerp(
			CFrame.new(),
			RotationRecoveryAlpha
		)

		-- Smoothly recover position to neutral
		CurrentPositionKick = CurrentPositionKick:Lerp(
			CFrame.new(),
			RecoveryAlpha
		)

		-- Reset targets
		TargetRotationKick = TargetRotationKick:Lerp(
			CFrame.new(),
			RotationRecoveryAlpha
		)

		TargetPositionKick = TargetPositionKick:Lerp(
			CFrame.new(),
			RecoveryAlpha
		)
		
	else
		-- Apply kick immediately (snappy kick) with frame-rate independent lerp
		local SnapAlpha = 1 - math.exp(-Config.KickSnapSpeed * DeltaTime)
		CurrentRotationKick = CurrentRotationKick:Lerp(
			TargetRotationKick,
			SnapAlpha
		)

		CurrentPositionKick = CurrentPositionKick:Lerp(
			TargetPositionKick,
			SnapAlpha
		)
	end

	-- Apply safety clamps during update as well (extra protection)
	CurrentRotationKick = ClampRotation(CurrentRotationKick)
	CurrentPositionKick = ClampPosition(CurrentPositionKick)
end

--[[
	Gets the combined kick CFrame (rotation and position)
	@return CFrame
]]
function GunKick.GetKick()
	return CurrentRotationKick * CurrentPositionKick
end

--[[
	Gets only the rotation kick CFrame
	@return CFrame
]]
function GunKick.GetRotationKick()
	return CurrentRotationKick
end

--[[
	Gets only the position kick CFrame
	@return CFrame
]]
function GunKick.GetPositionKick()
	return CurrentPositionKick
end

--[[
	Checks if currently kicking
	@return boolean
]]
function GunKick.IsKicking()
	return IsKicking
end

--[[
	Resets all kick values to neutral
]]
function GunKick.Reset()
	CurrentRotationKick = CFrame.new()
	CurrentPositionKick = CFrame.new()
	TargetRotationKick = CFrame.new()
	TargetPositionKick = CFrame.new()
	IsKicking = false
	KickStartTime = 0
	LastKickTime = 0
end

--[[
	Sets configuration values
	@param NewConfig table - Configuration overrides
]]
function GunKick.SetConfig(NewConfig)
	for Key, Value in pairs(NewConfig) do
		if Config[Key] ~= nil then
			Config[Key] = Value
		end
	end
end

--[[
	Gets the current configuration
	@return table - Copy of current configuration
]]
function GunKick.GetConfig()
	local ConfigCopy = {}
	for Key, Value in pairs(Config) do
		ConfigCopy[Key] = Value
	end
	return ConfigCopy
end

return GunKick