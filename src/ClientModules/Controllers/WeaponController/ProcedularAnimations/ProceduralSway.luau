--!native
--!optimize 2
--[[
	Aiming Sway Module
	Handles weapon sway during aiming with breathing simulation
	Frame-rate independent using delta time
--]]
local ProceduralSway = {}

-- Pre-cache math functions
local Sin = math.sin
local Cos = math.cos
local Exp = math.exp
local Log = math.log
local PI2 = math.pi * 2
local CF = CFrame.new

-- Configuration
local DefaultConfig = {
	AimTime = 0.15,           -- Time in seconds to reach aim position (99% completion)
	IdleTime = 0.2,           -- Time to return to idle
	SwaySpeed = 1,
	BreathRate = 0.5,
	SwayAmplitude = 0.01,
	CompletionPercent = 0.99  -- 0.99 = 99%, 0.95 = 95%, etc.
}

-- Conversion constant (calculated once)
local function CalculateLerpSpeed(aimTime, completionPercent)
	return -Log(1 - completionPercent) / aimTime
end

-- State Variables
local AimCFrame = CF()
local Elapsed = 0
local CurrentConfig = DefaultConfig
local AimLerpSpeed = CalculateLerpSpeed(DefaultConfig.AimTime, DefaultConfig.CompletionPercent)
local IdleLerpSpeed = CalculateLerpSpeed(DefaultConfig.IdleTime, DefaultConfig.CompletionPercent)

function ProceduralSway.UpdateAiming(PrimaryCFrame, TargetCFrame, DeltaTime)
	if not DeltaTime or DeltaTime <= 0 then
		return false
	end

	Elapsed = Elapsed + DeltaTime

	local SwaySpeed = CurrentConfig.SwaySpeed
	local BreathRate = CurrentConfig.BreathRate
	local SwayAmplitude = CurrentConfig.SwayAmplitude

	-- Calculate aim offset
	local offset = TargetCFrame:ToObjectSpace(PrimaryCFrame)

	-- Procedural breathing/sway
	local swayX = Sin(Elapsed * SwaySpeed * PI2) * SwayAmplitude
	local swayY = Cos(Elapsed * BreathRate * PI2) * (SwayAmplitude * 0.3)
	offset = offset * CF(swayX, swayY, 0)

	-- Frame-rate independent lerp
	local alpha = 1 - Exp(-AimLerpSpeed * DeltaTime)
	AimCFrame = AimCFrame:Lerp(offset, alpha)

	return true
end

function ProceduralSway.UpdateIdle(deltaTime)
	if not deltaTime or deltaTime <= 0 then
		return false
	end

	Elapsed = Elapsed + deltaTime

	local SwaySpeed = CurrentConfig.SwaySpeed
	local BreathRate = CurrentConfig.BreathRate
	local SwayAmplitude = CurrentConfig.SwayAmplitude
	
	-- Calculate idle breathing motion (same parameters as aiming)
	local swayX = Sin(Elapsed * SwaySpeed * PI2) * SwayAmplitude
	local swayY = Cos(Elapsed * BreathRate * PI2) * (SwayAmplitude * 0.3)
	local idleBreathing = CF(swayX, swayY, 0)

	-- Lerp toward idle breathing position
	local alpha = 1 - Exp(-IdleLerpSpeed * deltaTime)
	AimCFrame = AimCFrame:Lerp(idleBreathing, alpha)

	return true
end

function ProceduralSway.GetAimCF()
	return AimCFrame
end

function ProceduralSway.Reset()
	AimCFrame = CF()
	Elapsed = 0
end

function ProceduralSway.SetConfig(config)
	if not config or type(config) ~= "table" then
		return false
	end

	for key, value in pairs(config) do
		if CurrentConfig[key] ~= nil then
			CurrentConfig[key] = value
		end
	end

	-- Recalculate lerp speeds if timing changed
	if config.AimTime or config.CompletionPercent then
		AimLerpSpeed = CalculateLerpSpeed(CurrentConfig.AimTime, CurrentConfig.CompletionPercent)
	end
	if config.IdleTime or config.CompletionPercent then
		IdleLerpSpeed = CalculateLerpSpeed(CurrentConfig.IdleTime, CurrentConfig.CompletionPercent)
	end

	return true
end

function ProceduralSway.GetConfig()
	local copy = {}
	for key, value in pairs(CurrentConfig) do
		copy[key] = value
	end
	return copy
end

return ProceduralSway