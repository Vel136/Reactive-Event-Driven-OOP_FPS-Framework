--!native
--!optimize 2
--[[
	Walk Tilt Module
	Handles camera tilt based on movement direction
	Now independently manages Humanoid and Camera references
--]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local module = {}

local DefaultConfiguration = {
	-- 5 degrees max tilt
	MaxWalkTilt = math.rad(5),
	-- Lerp speed for smooth transitions
	WalkTiltLerpSpeed = 0.05,
	-- Auto-update on RenderStepped
	AutoUpdate = true,
	-- Internal state (do not set manually)
	WalkTiltCF = nil,
	_humanoid = nil,
	_camera = nil,
	_connection = nil,
}

local WalkTilt = {}

--[[
	Internal update function that uses stored references
]]
function WalkTilt._InternalUpdate(self: WalkTilt)
	if not self._humanoid or not self._camera then return end

	local moveDirection = self._humanoid.MoveDirection
	local cameraCFrame = self._camera.CFrame
	local relativeMove = cameraCFrame:VectorToObjectSpace(moveDirection)

	-- Calculate tilt based on left/right movement
	local tiltAmount = math.clamp(-relativeMove.X, -1, 1)
	local tiltAngle = tiltAmount * self.MaxWalkTilt

	self.WalkTiltCF = self.WalkTiltCF:Lerp(
		CFrame.Angles(0, 0, tiltAngle),
		self.WalkTiltLerpSpeed
	)
end

--[[
	Updates walking tilt effect based on movement direction
	Can be called manually or auto-updates if AutoUpdate is true
	@param humanoid Humanoid (optional) - Override humanoid for this update
	@param cameraCFrame CFrame (optional) - Override camera CFrame for this update
]]
function WalkTilt.Update(self: WalkTilt, humanoid, cameraCFrame)
	-- If parameters provided, use them temporarily
	if humanoid and cameraCFrame then
		local moveDirection = humanoid.MoveDirection
		local relativeMove = cameraCFrame:VectorToObjectSpace(moveDirection)

		local tiltAmount = math.clamp(-relativeMove.X, -1, 1)
		local tiltAngle = tiltAmount * self.MaxWalkTilt

		self.WalkTiltCF = self.WalkTiltCF:Lerp(
			CFrame.Angles(0, 0, tiltAngle),
			self.WalkTiltLerpSpeed
		)
	else
		-- Use stored references
		self:_InternalUpdate()
	end
end

--[[
	Sets the humanoid to track
	@param humanoid Humanoid
]]
function WalkTilt.SetHumanoid(self: WalkTilt, humanoid)
	self._humanoid = humanoid
end

--[[
	Sets the camera to use
	@param camera Camera
]]
function WalkTilt.SetCamera(self: WalkTilt, camera)
	self._camera = camera
end

--[[
	Gets the current humanoid
	@return Humanoid?
]]
function WalkTilt.GetHumanoid(self: WalkTilt)
	return self._humanoid
end

--[[
	Gets the current camera
	@return Camera?
]]
function WalkTilt.GetCamera(self: WalkTilt)
	return self._camera
end

--[[
	Automatically finds and sets the local player's humanoid and camera
	@return boolean - Success status
]]
function WalkTilt.AutoSetup(self: WalkTilt)
	local player = Players.LocalPlayer
	if not player then return false end

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")

	self._humanoid = humanoid
	self._camera = workspace.CurrentCamera

	-- Handle character respawn
	player.CharacterAdded:Connect(function(newCharacter)
		self._humanoid = newCharacter:WaitForChild("Humanoid")
	end)

	return true
end

--[[
	Enables or disables auto-update
	@param enabled boolean
]]
function WalkTilt.SetAutoUpdate(self: WalkTilt, enabled: boolean)
	self.AutoUpdate = enabled

	if enabled and not self._connection then
		self._connection = RunService.RenderStepped:Connect(function()
			self:_InternalUpdate()
		end)
	elseif not enabled and self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

--[[
	Gets the walk tilt CFrame
	@return CFrame
]]
function WalkTilt.GetTilt(self: WalkTilt)
	return self.WalkTiltCF
end

--[[
	Gets the walk tilt CFrame (alias for GetTilt)
	@return CFrame
]]
function WalkTilt.GetCFrame(self: WalkTilt)
	return self.WalkTiltCF
end

--[[
	Resets walk tilt to neutral
]]
function WalkTilt.Reset(self: WalkTilt)
	self.WalkTiltCF = CFrame.new()
end

--[[
	Updates configuration values
	@param config table - Configuration overrides
]]
function WalkTilt.SetConfig(self: WalkTilt, config)
	if not config or type(config) ~= "table" then
		return false
	end

	for key, value in pairs(config) do
		if key == "AutoUpdate" then
			self:SetAutoUpdate(value)
		elseif self[key] ~= nil and not key:match("^_") and key ~= "WalkTiltCF" then
			self[key] = value
		end
	end

	return true
end

--[[
	Gets current tilt angle in degrees (for debugging)
	@return number
]]
function WalkTilt.GetTiltAngle(self: WalkTilt)
	local _, _, z = self.WalkTiltCF:ToEulerAnglesXYZ()
	return math.deg(z)
end

--[[
	Creates a clone of this WalkTilt instance with the same configuration
	@return WalkTilt - A new instance with copied settings
]]
function WalkTilt.Clone(self: WalkTilt)
	local clonedConfig = {
		MaxWalkTilt = self.MaxWalkTilt,
		WalkTiltLerpSpeed = self.WalkTiltLerpSpeed,
		AutoUpdate = false, -- Start disabled to avoid double connections
	}
	return module.new(clonedConfig)
end

--[[
	Destroys the WalkTilt instance and cleans up connections
]]
function WalkTilt.Destroy(self: WalkTilt)
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self._humanoid = nil
	self._camera = nil
end

--[[
	Creates a new WalkTilt instance
	@param Configuration table - Configuration overrides
	@return WalkTilt
]]
function module.new(Configuration: Configuration): WalkTilt
	local walkTilt = table.clone(WalkTilt) :: WalkTilt

	-- Initialize configuration
	walkTilt.MaxWalkTilt = Configuration and Configuration.MaxWalkTilt or DefaultConfiguration.MaxWalkTilt
	walkTilt.WalkTiltLerpSpeed = Configuration and Configuration.WalkTiltLerpSpeed or DefaultConfiguration.WalkTiltLerpSpeed
	walkTilt.AutoUpdate = Configuration and Configuration.AutoUpdate or DefaultConfiguration.AutoUpdate

	-- Initialize state
	walkTilt.WalkTiltCF = CFrame.new()
	walkTilt._humanoid = nil
	walkTilt._camera = nil
	walkTilt._connection = nil

	-- Set up auto-update if enabled
	if walkTilt.AutoUpdate then
		walkTilt:SetAutoUpdate(true)
	end

	return walkTilt
end

export type Configuration = typeof(DefaultConfiguration)
export type WalkTilt = typeof(WalkTilt) & Configuration

return module