--!native
--!optimize 2
--[[
	Motion Blur Module
	Handles motion blur based on mouse movement
	Version 1.0
--]]

local module = {}

-- Services
local LightingServ = game:GetService("Lighting")
local UIS = game:GetService("UserInputService")

-- Pre-cache
local abs = math.abs
local clamp = math.clamp

-- Default Configuration
local DefaultBlurConfig = {
	-- Blur Settings
	BlurMultiplier = 1,           -- Scales blur intensity
	MaxBlur = 10,                 -- Maximum blur size

	-- Drift Settings
	DriftMin = -50,               -- Minimum drift value
	DriftMax = 50,                -- Maximum drift value
	DriftSmoothness = 0.1,        -- How smoothly drift changes (0-1)

	-- Blur Smoothness
	BlurSmoothness = 0.2,         -- How smoothly blur size changes (0-1)
}

-- Utility: Linear interpolation
local function NumLerp(num1: number, num2: number, rate: number): number
	return num1 + (num2 - num1) * rate
end

-- Type Definitions
export type Configuration = {
	-- Blur Settings
	BlurMultiplier: number?,      -- Scales blur intensity (default: 1)
	MaxBlur: number?,             -- Maximum blur size (default: 10)

	-- Drift Settings
	DriftMin: number?,            -- Minimum drift value (default: -50)
	DriftMax: number?,            -- Maximum drift value (default: 50)
	DriftSmoothness: number?,     -- How smoothly drift changes, 0-1 (default: 0.1)

	-- Blur Smoothness
	BlurSmoothness: number?,      -- How smoothly blur size changes, 0-1 (default: 0.2)
}

local MotionBlur = {
	BlurMultiplier = DefaultBlurConfig.BlurMultiplier,
	MaxBlur = DefaultBlurConfig.MaxBlur,
	DriftMin = DefaultBlurConfig.DriftMin,
	DriftMax = DefaultBlurConfig.DriftMax,
	DriftSmoothness = DefaultBlurConfig.DriftSmoothness,
	BlurSmoothness = DefaultBlurConfig.BlurSmoothness,

	Drift = 0,
	SmoothedDrift = 0,
	BlurEffect = nil :: BlurEffect?,
}

local function SetupBlur(): BlurEffect
	local existingBlur: BlurEffect? = LightingServ:FindFirstChildOfClass('BlurEffect')

	if not existingBlur then
		local newBlur = Instance.new("BlurEffect")
		newBlur.Size = 0
		newBlur.Name = 'MotionBlur'
		newBlur.Enabled = true
		newBlur.Parent = LightingServ
		
		existingBlur = newBlur
	end

	return existingBlur
end

function MotionBlur.Update(self: MotionBlur, deltaTime: number)
	if not self.BlurEffect then
		warn("MotionBlur: BlurEffect not initialized")
		return
	end

	-- Get mouse delta
	local mouseDelta = UIS:GetMouseDelta()

	-- Calculate target drift from horizontal mouse movement
	local targetDrift = clamp(mouseDelta.X, self.DriftMin, self.DriftMax)

	-- Smooth drift calculation (double smoothing like original)
	local driftLerpRate = clamp(self.DriftSmoothness * deltaTime * 60, 0, 1)
	self.Drift = NumLerp(self.Drift, targetDrift, driftLerpRate)

	local smoothDriftLerpRate = clamp(self.DriftSmoothness * deltaTime * 30, 0, 1)
	self.SmoothedDrift = NumLerp(self.SmoothedDrift, self.Drift, smoothDriftLerpRate)

	-- Calculate blur size
	local targetBlurSize = clamp(
		abs(self.SmoothedDrift * self.BlurMultiplier), 
		0, 
		self.MaxBlur
	)

	-- Smooth blur transition
	local blurLerpRate = clamp(self.BlurSmoothness * deltaTime * 60, 0, 1)
	self.BlurEffect.Size = NumLerp(self.BlurEffect.Size, targetBlurSize, blurLerpRate)
end

function MotionBlur.SetConfig(self: MotionBlur, Configuration: Configuration)
	self.BlurMultiplier = Configuration.BlurMultiplier or self.BlurMultiplier
	self.MaxBlur = Configuration.MaxBlur or self.MaxBlur
	self.DriftMin = Configuration.DriftMin or self.DriftMin
	self.DriftMax = Configuration.DriftMax or self.DriftMax
	self.DriftSmoothness = Configuration.DriftSmoothness or self.DriftSmoothness
	self.BlurSmoothness = Configuration.BlurSmoothness or self.BlurSmoothness


	return true
end

function MotionBlur.Reset(self: MotionBlur)
	self.Drift = 0
	self.SmoothedDrift = 0
	if self.BlurEffect then
		self.BlurEffect.Size = 0
	end
end

function MotionBlur.Destroy(self: MotionBlur)
	if self.BlurEffect then
		self.BlurEffect:Destroy()
		self.BlurEffect = nil
	end
end

function module.new(Configuration: Configuration?): MotionBlur
	local instance = setmetatable({},{__index = MotionBlur})

	instance.BlurMultiplier = Configuration and Configuration.BlurMultiplier or DefaultBlurConfig.BlurMultiplier
	instance.MaxBlur = Configuration and Configuration.MaxBlur or DefaultBlurConfig.MaxBlur
	instance.DriftMin = Configuration and Configuration.DriftMin or DefaultBlurConfig.DriftMin
	instance.DriftMax = Configuration and Configuration.DriftMax or DefaultBlurConfig.DriftMax
	instance.DriftSmoothness = Configuration and Configuration.DriftSmoothness or DefaultBlurConfig.DriftSmoothness
	instance.BlurSmoothness = Configuration and Configuration.BlurSmoothness or DefaultBlurConfig.BlurSmoothness
	

	instance.Drift = 0
	instance.SmoothedDrift = 0
	instance.BlurEffect = SetupBlur()

	return instance :: MotionBlur
end

export type MotionBlur = typeof(setmetatable({},{__index = MotionBlur}))

return module