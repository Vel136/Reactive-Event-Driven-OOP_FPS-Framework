-- DOFManager.lua
--[[
	Handles DOF Effect
]]
local Identity = "DepthOfField_Manager"
local DOFManager = {}  -- This will become the DepthOfField instance
DOFManager.__type = Identity

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- References
local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- Modules
local DepthOfFieldModule = require(Utilities.DepthOfField)

-- Additional Modules
local LogService = require(Utilities.Logger)
local Logger = LogService.new(Identity, false)

local Camera = workspace.CurrentCamera

local Configuration = {
	-- Slower, more deliberate spring motion
	Damping = 0.95,              -- Very smooth, minimal overshoot
	Stiffness = 5,               -- Gentle transitions

	-- Moderate blur intensities for tactical awareness
	NearIntensity = 0.1,        -- Subtle near blur
	FarIntensity = 0.35,         -- Moderate far blur
	InFocusRadius = 14,          -- Wider focus area for awareness

	-- Intensity Buildup - Gentle and sustained
	IntensityBuildup = true,
	IntensityDamping = 0.85,     -- Very smooth recovery
	IntensityStiffness = 4,      -- Slow, gentle spring
	MaxNearIntensity = 0.7,      -- Moderate cap (less jarring)
	MaxFarIntensity = 0.6,
	IntensityDecayRate = 0.9999,   -- Slower decay for sustained effect

	-- Enhanced smoothness for deliberate movement
	FocusDeadzone = 1.5,         -- More responsive to small changes
	MaxFocusSpeed = 120,         -- Slower focus transitions
	FocusSmoothing = 0.45,       -- Heavy smoothing

	-- Feature toggles
	DynamicIntensity = true,
	MultiSampleRaycast = true,   -- Better accuracy for tactical positioning
	AdaptiveDamping = true,
	AdaptiveUpdateRate = true,
}

local DOF = DepthOfFieldModule.new(Camera, Configuration)
function DOFManager.GetDepthOfField()
	return DOF
end

function DOFManager._Initialize()
	Logger:Print("DepthOfField Effect Initialized.")
end

function DOFManager.GetBaseIntensity()
	return Configuration.NearIntensity, Configuration.FarIntensity
end

local instance = nil
local metatable = {__index = DOFManager}  

local function GetInstance()
	if not instance then
		instance = setmetatable({}, metatable)  -- Create a proxy table
		instance._Initialize()  -- This reassigns 'instance' to the DepthOfField object
	end
	return instance
end

export type DOFManager = typeof(setmetatable({},metatable))

return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify DOFManager singleton service", 2)
	end,
}) :: DOFManager