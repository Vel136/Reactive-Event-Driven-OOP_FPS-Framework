--[[
	Aiming Sway Module
	Handles aiming sway with breathing simulation (Frame-rate independent)
--]]
local AimingSway = {}

-- Configuration
local AIM_LERP_SPEED = 8 -- Changed to per-second rate
local SWAY_SPEED = 1
local BREATH_RATE = 1
local SWAY_AMPLITUDE = 0.01

-- State Variables
local AimCF = CFrame.new()

--[[
	Updates aiming sway with breathing simulation
	@param viewmodel Model - The weapon viewmodel
	@param AimPart BasePart - The aiming reference part
	@param aimingValues table - Optional aiming configuration values
]]
function AimingSway.UpdateAiming(viewmodel, AimPart,deltaTime, aimingValues)
	if not viewmodel or not AimPart then return false end

	aimingValues = aimingValues or {}
	local swaySpeed = aimingValues.SWAY_SPEED or SWAY_SPEED
	local breathRate = aimingValues.BREATH_RATE or BREATH_RATE
	local swayAmplitude = aimingValues.SWAY_AMPLITUDE or SWAY_AMPLITUDE
	local lerpSpeed = aimingValues.AIM_LERP_SPEED or AIM_LERP_SPEED
	
	local currentTime = os.clock()
	-- Calculate aim offset
	local offset = AimPart.CFrame:ToObjectSpace(viewmodel.PrimaryPart.CFrame)

	-- Apply natural breathing/sway simulation
	local swayX = math.sin(currentTime * swaySpeed) * swayAmplitude
	local swayY = math.cos(currentTime * breathRate * 0.5) * (swayAmplitude * 0.3)
	offset = offset * CFrame.new(swayX, swayY, 0)

	-- Frame-rate independent lerp
	-- Formula: alpha = 1 - exp(-speed * deltaTime)
	local alpha = 1 - math.exp(-lerpSpeed * deltaTime)
	AimCF = AimCF:Lerp(offset, alpha)
end

function AimingSway.UpdateIdle(deltaTime)
	-- Calculate delta time
	local currentTime = os.clock()

	-- Frame-rate independent lerp back to neutral
	local alpha = 1 - math.exp(-AIM_LERP_SPEED * deltaTime)
	AimCF = AimCF:Lerp(CFrame.new(), alpha)
end

--[[
	Gets the aim offset CFrame
	@return CFrame
]]
function AimingSway.GetAimCF()
	return AimCF
end

--[[
	Resets the aiming sway to neutral
]]
function AimingSway.Reset()
	AimCF = CFrame.new()
	lastUpdateTime = os.clock()
end

--[[
	Sets configuration values
	@param config table - Configuration overrides
]]
function AimingSway.SetConfig(config)
	if config.AIM_LERP_SPEED then AIM_LERP_SPEED = config.AIM_LERP_SPEED end
	if config.SWAY_SPEED then SWAY_SPEED = config.SWAY_SPEED end
	if config.BREATH_RATE then BREATH_RATE = config.BREATH_RATE end
	if config.SWAY_AMPLITUDE then SWAY_AMPLITUDE = config.SWAY_AMPLITUDE end
end

return AimingSway