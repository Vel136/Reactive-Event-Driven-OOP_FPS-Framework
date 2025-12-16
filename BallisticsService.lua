-- BallisticsService.lua
--[[
	Central manager for all bullets fired in the game
	Singleton service that handles FastCast for all weapons
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utilities = ReplicatedStorage.SharedModules.Utilities
local FastCast = require(Utilities.FastCastRedux)
local Logger = require(Utilities:FindFirstChild("LogService"))

local BallisticsService = {}
BallisticsService.__index = BallisticsService
FastCast.VisualizeCasts = true
-- Private singleton instance
local instance

--[[
	Gets or creates the singleton instance
]]
local function GetInstance()
	if not instance then
		instance = setmetatable({}, BallisticsService)
		instance:_Initialize()
	end
	return instance
end

--[[
	Internal: Initializes the service
]]
function BallisticsService:_Initialize()
	-- Core FastCast
	self.Caster = FastCast.new()
	self.ActiveBullets = {} -- [cast] = {Weapon, Signals, StartTime}

	-- Default behavior
	self.DefaultBehavior = FastCast.newBehavior()
	self.DefaultBehavior.MaxDistance = 500
	self.DefaultBehavior.Acceleration = Vector3.new(0, -workspace.Gravity, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	self.DefaultBehavior.RaycastParams = params

	-- Connect events once for all bullets
	self.Caster.RayHit:Connect(function(cast, result, velocity, bullet)
		self:_OnRayHit(cast, result, velocity, bullet)
	end)

	self.Caster.LengthChanged:Connect(function(cast, lastPoint, direction, length, velocity, bullet)
		self:_OnLengthChanged(cast, lastPoint, direction, length, velocity, bullet)
	end)

	self.Caster.CastTerminating:Connect(function(cast)
		self:_OnCastTerminating(cast)
	end)

	Logger.Print("[BallisticsService] Initialized","[BallisticsService]")
end

--[[
	Internal: Handles RayHit event
]]
function BallisticsService:_OnRayHit(cast, result, velocity, bullet)
	local data = self.ActiveBullets[cast]
	if not data then return end

	-- Call weapon's hit handler if it exists
	if data.Weapon and data.Weapon._OnBulletHit then
		data.Weapon:_OnBulletHit(cast, result, velocity, bullet)
	end

	-- Clean up after hit
	self.ActiveBullets[cast] = nil
end

--[[
	Internal: Handles LengthChanged event
]]
function BallisticsService:_OnLengthChanged(cast, lastPoint, direction, length, velocity, bullet)
	local data = self.ActiveBullets[cast]
	if not data then return end

	-- Call weapon's travel handler if it exists
	if data.Weapon and data.Weapon._OnBulletTravel then
		data.Weapon:_OnBulletTravel(cast, lastPoint, direction, length, velocity, bullet)
	end
end

--[[
	Internal: Handles CastTerminating event
]]
function BallisticsService:_OnCastTerminating(cast)
	-- Clean up when bullet terminates without hitting anything
	if self.ActiveBullets[cast] then
		self.ActiveBullets[cast] = nil
	end
end

--[[ 
	Fire a bullet
	@param weapon: Weapon instance
	@param onHitSignal: Signal? (optional)
	@param onLengthChangedSignal: Signal? (optional)
	@param origin: Vector3
	@param direction: Vector3 (should be normalized)
	@param speed: number? (optional)
	@param behavior: FastCastBehavior? (optional)
	@return FastCast.ActiveCast
]]
function BallisticsService:Fire(weapon, origin, direction, speed, behavior)
	if not weapon or not origin or not direction then
		Logger.Warn("[BallisticsService] Invalid Fire parameters","[BallisticsService]")
		return
	end

	local bulletSpeed = speed or (weapon.Data and weapon.Data.BulletSpeed) or 1000
	local castBehavior = behavior or self.DefaultBehavior

	-- Ensure direction is normalized
	local normalizedDirection = direction.Unit

	-- Fire the bullet
	local cast = self.Caster:Fire(origin, normalizedDirection, bulletSpeed, castBehavior)

	-- Store bullet data
	self.ActiveBullets[cast] = {
		Weapon = weapon,
		StartTime = os.clock(),
		Origin = origin,
		Direction = normalizedDirection,
	}

	return cast
end

--[[
	Gets the number of active bullets
	@return number
]]
function BallisticsService:GetActiveBulletCount(): number
	local count = 0
	for _ in pairs(self.ActiveBullets) do
		count += 1
	end
	return count
end

--[[
	Gets all active bullets
	@return table
]]
function BallisticsService:GetActiveBullets(): {[any]: any}
	return self.ActiveBullets
end

--[[
	Clears a specific bullet
	@param cast: ActiveCast
]]
function BallisticsService:ClearBullet(cast)
	if self.ActiveBullets[cast] then
		self.ActiveBullets[cast] = nil
	end
end

--[[
	Clears all active bullets (use with caution)
]]
function BallisticsService:ClearAll()
	for cast, _ in pairs(self.ActiveBullets) do
		-- Terminate the cast if possible
		if cast and typeof(cast) == "table" and cast.Terminate then
			pcall(function()
				cast:Terminate()
			end)
		end
	end

	self.ActiveBullets = {}
	Logger.Print("[BallisticsService] Cleared all bullets","[BallisticsService]")
end

--[[
	Cleanup old bullets that may be stuck (safety measure)
	@param maxAge: number - Maximum age in seconds before cleanup
]]
function BallisticsService:CleanupOldBullets(maxAge: number?)
	maxAge = maxAge or 10 -- Default 10 seconds
	local now = os.clock()
	local cleaned = 0

	for cast, data in pairs(self.ActiveBullets) do
		if data.StartTime and (now - data.StartTime) > maxAge then
			self.ActiveBullets[cast] = nil
			cleaned += 1
		end
	end

	if cleaned > 0 then
		Logger.Warn(string.format("[BallisticsService] Cleaned up %d old bullets", cleaned),"[BallisticsService]")
	end
end

-- Return the singleton getter
return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("[BallisticsService] Cannot modify singleton service","[BallisticsService]")
	end
})