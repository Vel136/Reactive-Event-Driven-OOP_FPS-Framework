--!native
--!optimize 2
--[[
	GunKick Module
	Handles procedural gun recoil with automatic recovery (Frame-rate independent)
	Call Kick() from external scripts to trigger recoil
--]]

local module = {}

local DefaultConfiguration = {
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
		X = math.rad(10), -- Max 10 degrees upward
		Y = math.rad(20), -- Max 20 degrees left/right
		Z = math.rad(10), -- Max 10 degrees roll
	},

	MaxPosition = {
		X = 0.5, -- Max half stud left/right
		Y = 0.5, -- Max half stud up/down
		Z = 1.0, -- Max 1 stud backward
	},

	-- Internal state (do not set manually)
	CurrentRotationKick = nil,
	CurrentPositionKick = nil,
	TargetRotationKick = nil,
	TargetPositionKick = nil,
	IsKicking = nil,
	KickStartTime = nil,
	LastKickTime = nil,
}

-- Random number generator
local Random = Random.new()

-- Helper functions
local function RandomRange(Min, Max)
	return Min + Random:NextNumber() * (Max - Min)
end

local function Clamp(Value, Min, Max)
	return math.min(math.max(Value, Min), Max)
end

local function GetAnglesFromCFrame(CF)
	local X, Y, Z = CF:ToEulerAnglesXYZ()
	return X, Y, Z
end

local GunKick = {}

--[[
	Clamps a CFrame's rotation to maximum allowed values
	@param CF CFrame
	@return CFrame - Clamped CFrame
]]
function GunKick.ClampRotation(self : GunKick, CF)
	local X, Y, Z = GetAnglesFromCFrame(CF)

	-- Clamp each axis
	X = Clamp(X, -self.MaxRotation.X, self.MaxRotation.X)
	Y = Clamp(Y, -self.MaxRotation.Y, self.MaxRotation.Y)
	Z = Clamp(Z, -self.MaxRotation.Z, self.MaxRotation.Z)

	return CFrame.Angles(X, Y, Z)
end

--[[
	Clamps a CFrame's position to maximum allowed values
	@param CF CFrame
	@return CFrame - Clamped CFrame
]]
function GunKick.ClampPosition(self : GunKick, CF)
	local Pos = CF.Position

	local X = Clamp(Pos.X, -self.MaxPosition.X, self.MaxPosition.X)
	local Y = Clamp(Pos.Y, -self.MaxPosition.Y, self.MaxPosition.Y)
	local Z = Clamp(Pos.Z, -self.MaxPosition.Z, self.MaxPosition.Z)

	return CFrame.new(X, Y, Z)
end

--[[
	Triggers a gun kick with random recoil
	Call this function when the gun fires
	@param Intensity number - Optional intensity multiplier (default 1.0)
]]
function GunKick.Apply(self : GunKick, Intensity)
	Intensity = Intensity or 1.0
	local FinalIntensity = self.KickIntensity * Intensity

	-- Generate random rotation kick
	local RotX = RandomRange(self.Rotation.X.Min, self.Rotation.X.Max) * FinalIntensity
	local RotY = RandomRange(self.Rotation.Y.Min, self.Rotation.Y.Max) * FinalIntensity
	local RotZ = RandomRange(self.Rotation.Z.Min, self.Rotation.Z.Max) * FinalIntensity

	-- Generate random position kick
	local PosX = RandomRange(self.Position.X.Min, self.Position.X.Max) * FinalIntensity
	local PosY = RandomRange(self.Position.Y.Min, self.Position.Y.Max) * FinalIntensity
	local PosZ = RandomRange(self.Position.Z.Min, self.Position.Z.Max) * FinalIntensity

	-- Add to current kick (allows for kick stacking during rapid fire)
	self.TargetRotationKick = self.TargetRotationKick * CFrame.Angles(RotX, RotY, RotZ)
	self.TargetPositionKick = self.TargetPositionKick * CFrame.new(PosX, PosY, PosZ)

	-- Apply safety clamps to prevent extreme rotations
	self.TargetRotationKick = self:ClampRotation(self.TargetRotationKick)
	self.TargetPositionKick = self:ClampPosition(self.TargetPositionKick)

	self.IsKicking = true
	self.KickStartTime = os.clock()
	self.LastKickTime = os.clock()
end

--[[
	Updates the gun kick animation
	Call this every frame (RenderStepped)
	@param DeltaTime number - Time since last frame
]]
function GunKick.Update(self : GunKick, DeltaTime)
	local TimeSinceLastKick = os.clock() - self.LastKickTime

	-- If enough time has passed since last kick, start recovering
	if TimeSinceLastKick > 0.1 then
		-- Calculate frame-rate independent lerp alphas
		local RecoveryAlpha = 1 - math.exp(-self.RecoverySpeed * DeltaTime)
		local RotationRecoveryAlpha = 1 - math.exp(-self.RotationRecoverySpeed * DeltaTime)

		-- Smoothly recover rotation to neutral
		self.CurrentRotationKick = self.CurrentRotationKick:Lerp(
			CFrame.new(),
			RotationRecoveryAlpha
		)

		-- Smoothly recover position to neutral
		self.CurrentPositionKick = self.CurrentPositionKick:Lerp(
			CFrame.new(),
			RecoveryAlpha
		)

		-- Reset targets
		self.TargetRotationKick = self.TargetRotationKick:Lerp(
			CFrame.new(),
			RotationRecoveryAlpha
		)

		self.TargetPositionKick = self.TargetPositionKick:Lerp(
			CFrame.new(),
			RecoveryAlpha
		)

	else
		-- Apply kick immediately (snappy kick) with frame-rate independent lerp
		local SnapAlpha = 1 - math.exp(-self.KickSnapSpeed * DeltaTime)
		self.CurrentRotationKick = self.CurrentRotationKick:Lerp(
			self.TargetRotationKick,
			SnapAlpha
		)

		self.CurrentPositionKick = self.CurrentPositionKick:Lerp(
			self.TargetPositionKick,
			SnapAlpha
		)
	end

	-- Apply safety clamps during update as well (extra protection)
	self.CurrentRotationKick = self:ClampRotation(self.CurrentRotationKick)
	self.CurrentPositionKick = self:ClampPosition(self.CurrentPositionKick)
end

--[[
	Gets the combined kick CFrame (rotation and position)
	@return CFrame
]]
function GunKick.GetKick(self : GunKick)
	return self.CurrentRotationKick * self.CurrentPositionKick
end

--[[
	Gets the combined kick CFrame (alias for GetKick)
	@return CFrame
]]
function GunKick.GetCFrame(self : GunKick)
	return self.CurrentRotationKick * self.CurrentPositionKick
end

--[[
	Gets only the rotation kick CFrame
	@return CFrame
]]
function GunKick.GetRotationKick(self : GunKick)
	return self.CurrentRotationKick
end

--[[
	Gets only the position kick CFrame
	@return CFrame
]]
function GunKick.GetPositionKick(self : GunKick)
	return self.CurrentPositionKick
end

--[[
	Checks if currently kicking
	@return boolean
]]
function GunKick.IsKicking(self : GunKick)
	return self.IsKicking
end

--[[
	Gets debug information
	@return table
]]
function GunKick.GetDebugInfo(self : GunKick)
	local rotX, rotY, rotZ = GetAnglesFromCFrame(self.CurrentRotationKick)
	local pos = self.CurrentPositionKick.Position

	return {
		IsKicking = self.IsKicking,
		TimeSinceLastKick = os.clock() - self.LastKickTime,
		CurrentRotation = {
			X = math.deg(rotX),
			Y = math.deg(rotY),
			Z = math.deg(rotZ)
		},
		CurrentPosition = {
			X = pos.X,
			Y = pos.Y,
			Z = pos.Z
		}
	}
end

--[[
	Resets all kick values to neutral
]]
function GunKick.Reset(self : GunKick)
	self.CurrentRotationKick = CFrame.new()
	self.CurrentPositionKick = CFrame.new()
	self.TargetRotationKick = CFrame.new()
	self.TargetPositionKick = CFrame.new()
	self.IsKicking = false
	self.KickStartTime = 0
	self.LastKickTime = 0
end

--[[
	Updates configuration values
	@param config table - Configuration overrides
]]
function GunKick.SetConfig(self : GunKick, config : Configuration)
	if not config or type(config) ~= "table" then
		return false
	end

	for key, value in pairs(config) do
		if self[key] ~= nil and key ~= "CurrentRotationKick" and key ~= "CurrentPositionKick" 
			and key ~= "TargetRotationKick" and key ~= "TargetPositionKick" 
			and key ~= "IsKicking" and key ~= "KickStartTime" and key ~= "LastKickTime" then
			self[key] = value
		end
	end

	return true
end

--[[
	Creates a new GunKick instance
	@param Configuration table - Configuration overrides
	@return GunKick
]]
function module.new(Configuration : Configuration) : GunKick
	local gunKick = table.clone(GunKick) :: GunKick

	-- Initialize configuration
	gunKick.KickIntensity = Configuration and Configuration.KickIntensity or DefaultConfiguration.KickIntensity
	gunKick.RecoverySpeed = Configuration and Configuration.RecoverySpeed or DefaultConfiguration.RecoverySpeed
	gunKick.RotationRecoverySpeed = Configuration and Configuration.RotationRecoverySpeed or DefaultConfiguration.RotationRecoverySpeed
	gunKick.KickSnapSpeed = Configuration and Configuration.KickSnapSpeed or DefaultConfiguration.KickSnapSpeed

	-- Deep copy rotation ranges
	gunKick.Rotation = {
		X = Configuration and Configuration.Rotation and Configuration.Rotation.X or {
			Min = DefaultConfiguration.Rotation.X.Min,
			Max = DefaultConfiguration.Rotation.X.Max
		},
		Y = Configuration and Configuration.Rotation and Configuration.Rotation.Y or {
			Min = DefaultConfiguration.Rotation.Y.Min,
			Max = DefaultConfiguration.Rotation.Y.Max
		},
		Z = Configuration and Configuration.Rotation and Configuration.Rotation.Z or {
			Min = DefaultConfiguration.Rotation.Z.Min,
			Max = DefaultConfiguration.Rotation.Z.Max
		},
	}

	-- Deep copy position ranges
	gunKick.Position = {
		X = Configuration and Configuration.Position and Configuration.Position.X or {
			Min = DefaultConfiguration.Position.X.Min,
			Max = DefaultConfiguration.Position.X.Max
		},
		Y = Configuration and Configuration.Position and Configuration.Position.Y or {
			Min = DefaultConfiguration.Position.Y.Min,
			Max = DefaultConfiguration.Position.Y.Max
		},
		Z = Configuration and Configuration.Position and Configuration.Position.Z or {
			Min = DefaultConfiguration.Position.Z.Min,
			Max = DefaultConfiguration.Position.Z.Max
		},
	}

	-- Deep copy max rotation limits
	gunKick.MaxRotation = {
		X = Configuration and Configuration.MaxRotation and Configuration.MaxRotation.X or DefaultConfiguration.MaxRotation.X,
		Y = Configuration and Configuration.MaxRotation and Configuration.MaxRotation.Y or DefaultConfiguration.MaxRotation.Y,
		Z = Configuration and Configuration.MaxRotation and Configuration.MaxRotation.Z or DefaultConfiguration.MaxRotation.Z,
	}

	-- Deep copy max position limits
	gunKick.MaxPosition = {
		X = Configuration and Configuration.MaxPosition and Configuration.MaxPosition.X or DefaultConfiguration.MaxPosition.X,
		Y = Configuration and Configuration.MaxPosition and Configuration.MaxPosition.Y or DefaultConfiguration.MaxPosition.Y,
		Z = Configuration and Configuration.MaxPosition and Configuration.MaxPosition.Z or DefaultConfiguration.MaxPosition.Z,
	}

	-- Initialize state
	gunKick.CurrentRotationKick = CFrame.new()
	gunKick.CurrentPositionKick = CFrame.new()
	gunKick.TargetRotationKick = CFrame.new()
	gunKick.TargetPositionKick = CFrame.new()
	gunKick.IsKicking = false
	gunKick.KickStartTime = 0
	gunKick.LastKickTime = 0

	return gunKick
end

export type Configuration = typeof(DefaultConfiguration)
export type GunKick = typeof(GunKick) & Configuration

return module