-- AnimationHandler.lua

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- References
local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- Additional Modules
local LogService = require(Utilities.Logger)


local Identity = "AnimationController"
local AnimationHandler = {}
AnimationHandler.__type = Identity


local Logger = LogService.new(Identity, true)

--[[
	Internal: Sets up AnimationController and Animator on the model
	@return Animator instance
]]
function AnimationHandler:_InitializeAnimator(): Animator
	local Controller = self.Model:FindFirstChildOfClass("AnimationController") or self.Model:FindFirstChildOfClass("Humanoid")

	if not Controller then
		Controller = Instance.new("AnimationController")
		Controller.Parent = self.Model
	end

	local Animator = Controller:FindFirstChildOfClass("Animator")

	if not Animator then
		Animator = Instance.new("Animator")
		Animator.Parent = Controller
	end

	return Animator
end

--[[
	Loads a single animation
	@param Animation - The Animation instance to load
	@param Identifier - Key to store the track under
	@param Priority - Optional AnimationPriority
	@param Loop - Whether the animation should loop
	@return AnimationTrack
]]
function AnimationHandler:LoadAnimation(
	Animation: Animation, 
	Identifier: string | number,
	Priority: Enum.AnimationPriority?,
	Loop: boolean?
): AnimationTrack
	if not self.Animator then
		Logger:Warn("Animator not initialized", Identity)
		return nil
	end

	if not Animation then
		Logger:Warn("Invalid animation provided for: " .. tostring(Identifier), Identity)
		return nil
	end

	local Track = self.Animator:LoadAnimation(Animation)
	Track.Priority = Priority or Enum.AnimationPriority.Action
	Track.Looped = Loop or false

	self.AnimationTracks[Identifier] = Track

	Logger:Print("Loaded animation: " .. tostring(Identifier), Identity)

	return Track
end

--[[
	Loads multiple animations at once
	@param Animations - Table of animations with identifiers as keys
	@param PriorityMap - Optional table mapping identifiers to priorities
	@param LoopMap - Optional table mapping identifiers to loop settings
]]
function AnimationHandler:LoadAnimations(
	Animations: {[string | number]: Animation},
	PriorityMap: {[string | number]: Enum.AnimationPriority}?,
	LoopMap: {[string | number]: boolean}?
)
	if not Animations then
		Logger:Warn("No animations provided to load", Identity)
		return
	end

	local Count = 0

	for Identifier, Animation in pairs(Animations) do
		local Priority = PriorityMap and PriorityMap[Identifier]
		local Loop = LoopMap and LoopMap[Identifier]
		if self:LoadAnimation(Animation, Identifier, Priority, Loop) then
			Count += 1
		end

	end

	Logger:Print("Loaded " .. Count .. " animations", Identity)

	return true
end

--[[
	Plays an animation by identifier
	@param Identifier - The key of the animation to play
	@param FadeTime - Optional fade time (default: 0.3)
	@param Weight - Optional weight (default: 1)
	@param Speed - Optional speed (default: 1)
	@return AnimationTrack or nil
]]
function AnimationHandler:PlayAnimation(
	Identifier: string | number,
	FadeTime: number?,
	Weight: number?,
	Speed: number?
): AnimationTrack


	local Track = self.AnimationTracks[Identifier]

	if not Track then
		Logger:Warn("Animation not found: " .. tostring(Identifier), Identity)
		return nil
	end

	if Track.IsPlaying then
		Track:Stop(FadeTime or 0.1)
	end

	Track:Play(FadeTime or 0.3, Weight or 1, Speed or 1)

	self.CurrentState = Identifier
	self.IsTransitioning = true

	-- Handle completion for non-looped animations
	if not Track.Looped then
		task.delay(Track.Length / (Speed or 1), function()
			if self.CurrentState == Identifier then
				self.IsTransitioning = false
			end
		end)
	else
		self.IsTransitioning = false
	end

	Logger:Print("Playing animation: " .. tostring(Identifier), Identity)

	return Track
end

--[[
	Stops an animation by identifier
	@param Identifier - The key of the animation to stop
	@param FadeTime - Optional fade time (default: 0.3)
]]
function AnimationHandler:StopAnimation(Identifier: string | number, FadeTime: number?)
	local Track = self.AnimationTracks[Identifier]

	if not Track or not Track.IsPlaying then
		return
	end

	Track:Stop(FadeTime or 0.3)

	if self.CurrentState == Identifier then
		self.CurrentState = nil
		self.IsTransitioning = false
	end

	Logger:Print("Stopped animation: " .. tostring(Identifier), Identity)
end

--[[
	Stops all currently playing animations
	@param FadeTime - Optional fade time (default: 0.3)
]]
function AnimationHandler:StopAllAnimations(FadeTime: number?)
	for Identifier, Track in pairs(self.AnimationTracks) do
		if Track.IsPlaying then
			Track:Stop(FadeTime or 0.3)
		end
	end

	self.CurrentState = nil
	self.IsTransitioning = false

	Logger:Print("Stopped all animations", Identity)
end

--[[
	Checks if a specific animation is playing
	@param Identifier - The key of the animation to check
	@return boolean
]]
function AnimationHandler:IsPlaying(Identifier: string | number): boolean
	local Track = self.AnimationTracks[Identifier]
	return Track and Track.IsPlaying or false
end

--[[
	Gets the animation track by identifier
	@param Identifier - The key of the animation
	@return AnimationTrack or nil
]]
function AnimationHandler:GetTrack(Identifier: string | number): AnimationTrack?
	return self.AnimationTracks[Identifier]
end

--[[
	Gets the current playing state
	@return string | number | nil
]]
function AnimationHandler:GetCurrentState(): (string | number)?
	return self.CurrentState
end

--[[
	Adjusts the speed of a playing animation
	@param Identifier - The key of the animation
	@param Speed - New speed multiplier
]]
function AnimationHandler:SetSpeed(Identifier: string | number, Speed: number)
	local Track = self.AnimationTracks[Identifier]

	if not Track then
		Logger:Warn("Cannot set speed, animation not found: " .. tostring(Identifier), Identity)
		return
	end

	Track:AdjustSpeed(Speed)
end

--[[
	Adjusts the weight of a playing animation
	@param Identifier - The key of the animation
	@param Weight - New weight value
	@param FadeTime - Optional fade time for weight change
]]
function AnimationHandler:SetWeight(Identifier: string | number, Weight: number, FadeTime: number?)
	local Track = self.AnimationTracks[Identifier]

	if not Track then
		Logger:Warn("Cannot set weight, animation not found: " .. tostring(Identifier), Identity)
		return
	end

	Track:AdjustWeight(Weight, FadeTime or 0)
end

--[[
	Destroys the controller and cleans up all tracks
]]
function AnimationHandler:Destroy()
	Logger:Print("Destroying controller for model: " .. self.Model.Name, Identity)

	-- Stop and destroy all tracks
	for _, Track in pairs(self.AnimationTracks) do
		if Track.IsPlaying then
			Track:Stop(0)
		end
		Track:Destroy()
	end

	-- Clear references
	self.AnimationTracks = nil
	self.Animator = nil
	self.Model = nil
	self.CurrentState = nil

	setmetatable(self, nil)

	Logger:Print("Cleanup complete", Identity)
end

-- We lock the table
local module = {}

-- We dont reveal the metamethods
local metatable = {__index = AnimationHandler}

--[[
	Creates a new AnimationController instance
	@param Model - The viewmodel to attach animations to
	@return AnimationController instance
]]
function module.new(Model)
	local self = setmetatable({},metatable)
	if not Model then
		Logger:Warn("Invalid model provided", Identity)
		return nil
	end

	self.Model = Model
	self.Animator = nil
	self.AnimationTracks = {}
	self.CurrentState = nil
	self.IsTransitioning = false

	-- Initialize animator
	self.Animator = self:_InitializeAnimator()
	if not self.Animator then
		Logger:Warn("Failed to initialize animator", Identity)
		return nil
	end

	Logger:Print("Initialized for model: " .. Model.Name, Identity)

	return self
end

export type AnimationHandler = typeof(setmetatable({},metatable)) & {
	Model : Model,
	AnimationTracks : {[string|number] : AnimationTrack},
	CurrentState : any,
	IsTransitioning : boolean,

	-- Initialize animator
	Animator : Animator,
}

return table.freeze(module)