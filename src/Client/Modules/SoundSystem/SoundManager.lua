-- SoundManager 
--[[
	-- Handles Sound Lifecycle
	-- Sound blending
	-- Sound Playing & Stopping
]]
-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local SoundService = game:GetService('SoundService')
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService')
-- References
local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- Modules
local LogService = require(Utilities.Logger)
local Signal = require(Utilities.Signal)
local Throttle = require(Utilities.Throttle)


local Identity = "SoundManager"

local SoundManager = {}
SoundManager.__type = SoundManager

local Logger = LogService.new(Identity, false)
-- Internal state
local activeSounds = {}
local soundPools = {}
local blendingTweens = {}

-- Signals
SoundManager.SoundPlayed = Signal.new()
SoundManager.SoundStopped = Signal.new()
SoundManager.SoundBlended = Signal.new()

function SoundManager._Initialize()
	Logger:Debug("Initializing SoundManager")

	-- Cleanup on heartbeat
	RunService.Heartbeat:Connect(function()
		SoundManager._CleanupFinishedSounds()
	end)
end

-- Creates or retrieves a sound from pool
function SoundManager:GetPooledSound(soundId: string, parent: Instance): Sound
	if not soundPools[soundId] then
		soundPools[soundId] = {}
	end

	local pool = soundPools[soundId]

	-- Find available sound in pool
	for _, sound in ipairs(pool) do
		if not sound.IsPlaying then
			sound.Parent = parent
			return sound
		end
	end

	-- Create new sound if none available
	local newSound = Instance.new('Sound')
	newSound.SoundId = soundId
	newSound.Parent = parent
	table.insert(pool, newSound)

	return newSound
end

-- Play sound with optional position and properties
function SoundManager:PlaySound(sound: Sound | string, position: Vector3?, properties: {[string]: any}?)
	Throttle("PlaySound_" .. tostring(sound), 0.05, function()
		local soundInstance: Sound

		-- Handle string soundId or Sound instance
		if typeof(sound) == "string" then
			soundInstance = self:GetPooledSound(sound, workspace.Terrain)
		else
			soundInstance = sound:Clone()
			soundInstance.Parent = workspace.Terrain
		end

		-- Apply properties
		if properties then
			for key, value in pairs(properties) do
				soundInstance[key] = value
			end
		end

		-- Handle 3D positioning
		if position then
			local attachment = Instance.new('Attachment')
			attachment.Parent = workspace.Terrain
			attachment.WorldPosition = position
			soundInstance.Parent = attachment

			soundInstance.Ended:Once(function()
				attachment:Destroy()
			end)
		end

		soundInstance:Play()

		-- Track active sound
		table.insert(activeSounds, soundInstance)
		self.SoundPlayed:Fire(soundInstance)

		Logger:Debug("Playing sound: " .. tostring(soundInstance.SoundId))
	end)
end

-- Play sound at position with throttling
function SoundManager:PlaySoundAtPosition(sound: Sound, position: Vector3)
	Throttle("PlaySoundAtPos_" .. tostring(sound.SoundId), 0.05, function()
		local attachment = Instance.new('Attachment')
		attachment.Parent = workspace.Terrain
		attachment.WorldPosition = position

		local originalParent = sound.Parent
		sound.Parent = attachment
		sound:Play()

		sound.Ended:Once(function()
			sound.Parent = originalParent
			attachment:Destroy()
		end)

		table.insert(activeSounds, sound)
		self.SoundPlayed:Fire(sound)
	end)
end

-- Stop sound with optional fade out
function SoundManager:StopSound(sound: Sound, fadeTime: number?)
	if fadeTime and fadeTime > 0 then
		self:BlendSound(sound, {Volume = 0}, fadeTime, function()
			sound:Stop()
			self.SoundStopped:Fire(sound)
		end)
	else
		sound:Stop()
		self.SoundStopped:Fire(sound)
	end

	Logger:Debug("Stopping sound: " .. tostring(sound.SoundId))
end

-- Blend sound properties over time
function SoundManager:BlendSound(sound: Sound, properties: {[string]: any}, duration: number, callback: (()->())?)

	-- Cancel existing blend for this sound
	if blendingTweens[sound] then
		blendingTweens[sound]:Cancel()
	end

	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.InOut
	)

	local tween = TweenService:Create(sound, tweenInfo, properties)
	blendingTweens[sound] = tween

	tween.Completed:Once(function()
		blendingTweens[sound] = nil
		self.SoundBlended:Fire(sound, properties)

		if callback then
			callback()
		end
	end)

	tween:Play()

	Logger:Debug("Blending sound properties over " .. duration .. "s")
end

-- Crossfade between two sounds
function SoundManager:CrossfadeSound(fromSound: Sound, toSound: Sound, duration: number)
	-- Fade out current sound
	self:BlendSound(fromSound, {Volume = 0}, duration, function()
		fromSound:Stop()
	end)

	-- Fade in new sound
	toSound.Volume = 0
	toSound:Play()
	self:BlendSound(toSound, {Volume = toSound.Volume or 0.5}, duration)

	table.insert(activeSounds, toSound)

	Logger:Debug("Crossfading sounds over " .. duration .. "s")
end

-- Stop all sounds with optional fade
function SoundManager:StopAllSounds(fadeTime: number?)
	for _, sound in ipairs(activeSounds) do
		if sound and sound.Parent then
			self:StopSound(sound, fadeTime)
		end
	end

	Logger:Debug("Stopping all active sounds")
end

-- Pause sound with fade
function SoundManager:PauseSound(sound: Sound, fadeTime: number?)
	if fadeTime and fadeTime > 0 then
		local originalVolume = sound.Volume
		self:BlendSound(sound, {Volume = 0}, fadeTime, function()
			sound:Pause()
			sound.Volume = originalVolume
		end)
	else
		sound:Pause()
	end

	Logger:Debug("Pausing sound: " .. tostring(sound.SoundId))
end

-- Resume sound with fade
function SoundManager:ResumeSound(sound: Sound, fadeTime: number?)
	if fadeTime and fadeTime > 0 then
		local targetVolume = sound.Volume
		sound.Volume = 0
		sound:Resume()
		self:BlendSound(sound, {Volume = targetVolume}, fadeTime)
	else
		sound:Resume()
	end

	Logger:Log(Identity, "Resuming sound: " .. tostring(sound.SoundId))
end

-- Set sound group for a sound
function SoundManager:SetSoundGroup(sound: Sound, groupName: string)
	local soundGroup = SoundService:FindFirstChild(groupName)
	if soundGroup and soundGroup:IsA('SoundGroup') then
		sound.SoundGroup = soundGroup
		Logger:Debug("Set sound group: " .. groupName)
	else
		Logger:Warn("SoundGroup not found: " .. groupName)
	end
end

-- Cleanup finished sounds
function SoundManager._CleanupFinishedSounds()
	for i = #activeSounds, 1, -1 do
		local sound = activeSounds[i]
		if not sound or not sound.Parent or not sound.IsPlaying then
			table.remove(activeSounds, i)
		end
	end
end

-- Get random sound from array
function SoundManager:GetRandomSound(soundArray: {Sound}): Sound?
	if soundArray and #soundArray > 0 then
		return soundArray[math.random(1, #soundArray)]
	end
	return nil
end

-- Play random sound from array
function SoundManager:PlayRandomSound(soundArray: {Sound}, position: Vector3?, properties: {[string]: any}?)
	local randomSound = self:GetRandomSound(soundArray)
	if randomSound then
		self:PlaySound(randomSound, position, properties)
	end
end

-- Get active sounds count
function SoundManager:GetActiveSoundsCount(): number
	return #activeSounds
end

-- Clear sound pool
function SoundManager:ClearSoundPool(soundId: string?)
	if soundId then
		if soundPools[soundId] then
			for _, sound in ipairs(soundPools[soundId]) do
				sound:Destroy()
			end
			soundPools[soundId] = nil
		end
	else
		-- Clear all pools
		for _, pool in pairs(soundPools) do
			for _, sound in ipairs(pool) do
				sound:Destroy()
			end
		end
		soundPools = {}
	end

	Logger:Debug("Cleared sound pool" .. (soundId and ": " .. soundId or "s"))
end

-- Singleton instance
local metatable = {__index = SoundManager}
local instance

export type SoundManager = typeof(setmetatable({} , metatable))

local function GetInstance()
	if not instance then
		instance = setmetatable({}, metatable)
		instance._Initialize()
	end
	return instance
end

return setmetatable({}, {
	__index = function(_, Key)
		return GetInstance()[Key]
	end,
	__newindex = function()
		error("Cannot modify singleton service", 2)
	end
})