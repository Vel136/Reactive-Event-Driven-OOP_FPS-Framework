
local SCRIPT_NAME = "[WeaponAnimator]"

local ReplicatedStorage = game:GetService('ReplicatedStorage')

local Utilities = ReplicatedStorage.SharedModules.Utilities
local Janitor = require(Utilities.Janitor)
local Logger = require(Utilities.LogService)
local Promise = require(Utilities.Promise)
-- Import configuration
local Config = require(script.WeaponAnimatorConfig)
local Anims = Config.Animations
local Priority = Config.Priority
local FadeTime = Config.FadeTime
local States = Config.States

local WeaponAnimator = {}
WeaponAnimator.__index = WeaponAnimator

-- Export config for external access
WeaponAnimator.Config = Config
WeaponAnimator.Animations = Anims

--[[
	Creates a new WeaponAnimator instance
	@param weapon 
	@param viewmodel - The viewmodel Model in workspace
	@return WeaponAnimator instance or nil if invalid
]]
function WeaponAnimator.new(weapon, viewmodel: Model)
	if not weapon then
		Logger.Warn(SCRIPT_NAME .. " Invalid weapon provided")
		return nil
	end

	if not viewmodel then
		Logger.Warn(SCRIPT_NAME .. " Invalid viewmodel provided")
		return nil
	end

	local self = setmetatable({}, WeaponAnimator)

	-- Core references
	self.Weapon = weapon
	self.Promises = {
		Equip = nil,
		
	}
	self.Viewmodel = viewmodel
	self._Janitor = Janitor.new()

	-- Setup animator
	self.Animator = self:_SetupAnimator()
	if not self.Animator then
		Logger.Warn(SCRIPT_NAME .. " Failed to setup Animator")
		return nil
	end

	-- Animation tracks (cached) - uses numeric enum as keys
	self.Tracks = {}

	-- State tracking
	self.CurrentState = Anims.Idle
	self.CurrentPriority = Priority[Anims.Idle]
	self.IsTransitioning = false

	-- Load all animations
	self:_LoadAnimations()

	-- Bind to weapon signals
	self:_BindSignals()

	if Config.Debug.EnableLogging then
		Logger.Print(SCRIPT_NAME .. " 🎬 Initialized for: " .. weapon.Data.Name)
	end

	return self
end

--[[
	Internal: Sets up AnimationController and Animator
	@return Animator instance
]]
function WeaponAnimator:_SetupAnimator()
	local controller = self.Viewmodel:FindFirstChildOfClass("AnimationController")

	if not controller then
		controller = Instance.new("AnimationController")
		controller.Parent = self.Viewmodel
	end

	local animator = controller:FindFirstChildOfClass("Animator")

	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	return animator
end

--[[
	Internal: Loads and caches all weapon animations
]]
function WeaponAnimator:_LoadAnimations()
	local anims = self.Weapon.Data.Animations
	if not anims then return end

	-- Iterate through animation enum and load matching animations
	for animEnum, animName in pairs(States) do
		local animAsset = anims[animName]

		if animAsset then
			local track = self.Animator:LoadAnimation(animAsset)
			track.Priority = Config.RobloxPriority[animEnum] or Enum.AnimationPriority.Action
			track.Looped = Config.LoopSettings[animEnum] or false

			-- Store using numeric enum as key
			self.Tracks[animEnum] = track
		end
	end

	if Config.Debug.EnableLogging then
		Logger.Print(SCRIPT_NAME .. " Loaded " .. self:_CountTracks() .. " animations")
	end
end

--[[
	Internal: Counts loaded tracks
]]
function WeaponAnimator:_CountTracks()
	local count = 0
	for _ in pairs(self.Tracks) do
		count += 1
	end
	return count
end

--[[
	Internal: Binds to weapon signals
]]
function WeaponAnimator:_BindSignals()
	-- Fire signal
	if self.Tracks[Anims.Fire] then
		self._Janitor:Add(self.Weapon.Signals.OnFire:Connect(function()
			self:PlayAnimation(Anims.Fire)
		end))
	end

	-- Aim signal
	if self.Tracks[Anims.Aim] then
		self._Janitor:Add(self.Weapon.Signals.OnAimChanged:Connect(function(isAiming)
			if isAiming then
				self:PlayAnimation(Anims.Aim)
			else
				self:StopAnimation(Anims.Aim)
			end
		end))
	end

	-- Reload signal
	if self.Tracks[Anims.Reload] then
		self._Janitor:Add(self.Weapon.Signals.OnReload:Connect(function(Reload)
			
			self:PlayAnimation(Anims.Reload)
		end))
	end

	-- Equip signal
	if self.Tracks[Anims.Equip] then
		self._Janitor:Add(self.Weapon.Signals.OnEquipChanged:Connect(function(isEquipped)
			if isEquipped then
				self:PlayAnimation(Anims.Equip)
			else
				self:StopAllAnimations()
			end
		end))
	end
end

--[[
	Plays an animation with priority checking
	@param animEnum - Animation enum (use Animations.Fire, etc.)
	@param fadeTime - Optional fade time override
]]
function WeaponAnimator:PlayAnimation(animEnum: number, fadeTime: number?)
	local track : AnimationTrack = self.Tracks[animEnum]
	if not track then
		local animName = States[animEnum] or "Unknown"
		Logger.Warn(SCRIPT_NAME .. " Animation not found: " .. animName)
		return
	end

	local priority = Priority[animEnum] or Priority[Anims.Idle]

	-- Priority check: Can this animation interrupt current?
	if priority < self.CurrentPriority and self.IsTransitioning then
		if Config.Debug.LogPriorityBlocks then
			local animName = States[animEnum]
			Logger.Print(SCRIPT_NAME .. " Blocked " .. animName .. " (priority too low)")
		end
		return
	end

	-- Stop conflicting animations
	self:_StopConflictingAnimations(animEnum)

	if track.IsPlaying then
		track:Stop()
	end
	
	track:Play()
	
	-- Update state
	self.CurrentState = animEnum
	self.CurrentPriority = priority
	self.IsTransitioning = true

	-- Handle state after animation completes
	if not track.Looped then
		track.Ended:Once(function()
			self:_OnAnimationComplete(animEnum)
		end)
	else
		-- Looped animations are never "complete"
		self.IsTransitioning = false
	end

	if Config.Debug.LogTransitions then
		local animName = States[animEnum]
		Logger.Print(SCRIPT_NAME .. " Playing: " .. animName)
	end
end

--[[
	Stops a specific animation
	@param animEnum - Animation enum to stop
	@param fadeTime - Optional fade time override
]]
function WeaponAnimator:StopAnimation(animEnum: number, fadeTime: number?)
	local track = self.Tracks[animEnum]
	if not track or not track.IsPlaying then return end

	local fade = fadeTime or FadeTime.Normal
	track:Stop()

	-- If this was our current state, return to idle
	if self.CurrentState == animEnum then
		self.CurrentState = Anims.Idle
		self.CurrentPriority = Priority[Anims.Idle]
		self.IsTransitioning = false

		-- Play idle if available
		local idleTrack = self.Tracks[Anims.Idle]
		if idleTrack and not idleTrack.IsPlaying then
			idleTrack:Play(fade)
		end
	end

	if Config.Debug.LogTransitions then
		local animName = States[animEnum]
		Logger.Print(SCRIPT_NAME .. " Stopped: " .. animName)
	end
end

--[[
	Internal: Stops animations that conflict with the new one
	Uses TransitionRules from config
]]
function WeaponAnimator:_StopConflictingAnimations(newAnimEnum: number)
	local canInterrupt = Config.TransitionRules[newAnimEnum] or {}
	local stoppedAnims = {}

	for animEnum, track in pairs(self.Tracks) do
		if track.IsPlaying and animEnum ~= newAnimEnum then
			-- Check if new animation can interrupt this one
			local shouldStop = false
			for _, interruptibleEnum in ipairs(canInterrupt) do
				if animEnum == interruptibleEnum then
					shouldStop = true
					break
				end
			end

			if shouldStop then
				track:Stop()
				table.insert(stoppedAnims, States[animEnum])
			end
		end
	end

	-- Log interrupted animations
	if #stoppedAnims > 0 then
		local newAnimName = States[newAnimEnum]
		Logger.Print(SCRIPT_NAME .. " ⚠️ " .. newAnimName .. " interrupted: " .. table.concat(stoppedAnims, ", "))
	end
end

--[[
	Internal: Called when a non-looped animation completes
]]
function WeaponAnimator:_OnAnimationComplete(animEnum: number)
	self.IsTransitioning = false

	local animName = States[animEnum]
	Logger.Print(SCRIPT_NAME .. " ✅ Completed: " .. animName)

	-- Return to appropriate idle state based on current weapon state
	if animEnum == Anims.Equip or animEnum == Anims.Reload then
		self.Weapon.Signals.OnEquipCompleted:Fire()
		-- After equip/reload, play idle or aim
		if self.Weapon:IsAiming() and self.Tracks[Anims.Aim] then
			Logger.Print(SCRIPT_NAME .. " 🎯 Transitioning to Aim after " .. animName)
			self:PlayAnimation(Anims.Aim)
		elseif self.Tracks[Anims.Idle] then
			Logger.Print(SCRIPT_NAME .. " 💤 Transitioning to Idle after " .. animName)
			self.Tracks[Anims.Idle]:Play(FadeTime.Normal)
			self.CurrentState = Anims.Idle
			self.CurrentPriority = Priority[Anims.Idle]
		end
	elseif animEnum == Anims.Fire then
		-- Fire completes, return to previous state
		local aimTrack = self.Tracks[Anims.Aim]
		if aimTrack and aimTrack.IsPlaying then
			Logger.Print(SCRIPT_NAME .. " 🔫 Fire complete, maintaining Aim state")
			self.CurrentState = Anims.Aim
			self.CurrentPriority = Priority[Anims.Aim]
		else
			Logger.Print(SCRIPT_NAME .. " 🔫 Fire complete, returning to Idle")
			self.CurrentState = Anims.Idle
			self.CurrentPriority = Priority[Anims.Idle]
		end
	end
end

--[[
	Stops all animations immediately
]]
function WeaponAnimator:StopAllAnimations()
	for animEnum, track in pairs(self.Tracks) do
		if track.IsPlaying then
			track:Stop()
		end
	end

	self.CurrentState = Anims.Idle
	self.CurrentPriority = Priority[Anims.Idle]
	self.IsTransitioning = false
end

--[[
	Gets the current animation state
	@return number - Current animation enum
]]
function WeaponAnimator:GetCurrentState(): number
	return self.CurrentState
end

--[[
	Gets the current animation state name
	@return string - Current animation name
]]
function WeaponAnimator:GetCurrentStateName(): string
	return States[self.CurrentState] or "Unknown"
end

--[[
	Checks if a specific animation is playing
	@param animEnum - Animation enum to check
	@return boolean - Is playing
]]
function WeaponAnimator:IsPlaying(animEnum: number): boolean
	local track = self.Tracks[animEnum]
	return track and track.IsPlaying or false
end

--[[
	Destroys the animator and cleans up
]]
function WeaponAnimator:Destroy()
	local weaponName = self.Weapon and self.Weapon.Data.Name or "Unknown"

	if Config.Debug.EnableLogging then
		Logger.Print(SCRIPT_NAME .. " 💥 Destroying animator for: " .. weaponName)
	end

	-- Stop all animations
	self:StopAllAnimations()

	-- Cleanup janitor (disconnects all signals)
	self._Janitor:Destroy()

	-- Destroy all tracks
	for _, track in pairs(self.Tracks) do
		track:Destroy()
	end

	-- Clear references
	self.Weapon = nil
	self.Viewmodel = nil
	self.Animator = nil
	self.Tracks = nil

	setmetatable(self, nil)

	if Config.Debug.EnableLogging then
		Logger.Print(SCRIPT_NAME .. " ✨ Cleanup complete")
	end
end

return WeaponAnimator