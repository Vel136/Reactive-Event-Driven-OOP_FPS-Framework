-- Procedural Animations
local CameraRecoil = require(script.Parent.CameraRecoil)
local MouseSway = require(script.Parent.MouseSway)
local ProceduralSway = require(script.Parent.ProceduralSway)
local RotationalSway = require(script.Parent.RotationalSway)
local SpringSway = require(script.Parent.SpringSway)
local WeaponTilt = require(script.Parent.WeaponTilt)
local WalkTilt = require(script.Parent.WalkTilt)
local WalkBob = require(script.Parent.WalkBob)
local WeaponRecoil = require(script.Parent.WeaponRecoil)

local ProceduralAnimator = {
	-- Default built-in animations
	WeaponRecoil = WeaponRecoil.new(),
	CameraRecoil = CameraRecoil.new(),
	MouseSway = MouseSway.new(),
	ProceduralSway = ProceduralSway.new(),
	RotationalSway = RotationalSway.new(),
	SpringSway = SpringSway.new(),
	WeaponTilt = WeaponTilt.new(),
	WalkTilt = WalkTilt.new(),
	WalkBob = WalkBob.new(),

	-- Store custom registered animations
	_customAnimations = {},
	-- Store order of animation application
	_animationOrder = {
		"WeaponRecoil",
		"MouseSway",
		"RotationalSway",
		"SpringSway",
		"WeaponTilt",
		"WalkBob",
		"WalkTilt"
	}
}

--[[
	Register a custom procedural animation
	@param name string - Unique name for the animation
	@param animationInstance table - Instance of animation module (must have Update, GetCFrame, and Reset methods)
	@param insertIndex number? - Optional position in animation order (default: end)
	@return boolean - Success status
]]
function ProceduralAnimator.RegisterAnimation(self : ProceduralAnimator, name : string, animationInstance : any, insertIndex : number?)
	if not name or type(name) ~= "string" then
		warn("ProceduralAnimator: Animation name must be a string")
		return false
	end

	if not animationInstance then
		warn("ProceduralAnimator: Animation instance cannot be nil")
		return false
	end

	-- Validate that the animation has required methods
	if type(animationInstance.Update) ~= "function" then
		warn("ProceduralAnimator: Animation must have an Update method")
		return false
	end

	if type(animationInstance.GetCFrame) ~= "function" then
		warn("ProceduralAnimator: Animation must have a GetCFrame method")
		return false
	end

	if type(animationInstance.Reset) ~= "function" then
		warn("ProceduralAnimator: Animation must have a Reset method")
		return false
	end

	-- Check if name already exists
	if self[name] or table.find(self._animationOrder, name) then
		warn("ProceduralAnimator: Animation '" .. name .. "' already exists")
		return false
	end

	-- Register the animation
	self[name] = animationInstance
	table.insert(self._customAnimations, name)

	-- Add to animation order
	if insertIndex and insertIndex > 0 and insertIndex <= #self._animationOrder + 1 then
		table.insert(self._animationOrder, insertIndex, name)
	else
		table.insert(self._animationOrder, name)
	end

	return true
end

--[[
	Unregister a custom procedural animation
	@param name string - Name of the animation to remove
	@return boolean - Success status
]]
function ProceduralAnimator.UnregisterAnimation(self : ProceduralAnimator, name : string)
	if not name or type(name) ~= "string" then
		warn("ProceduralAnimator: Animation name must be a string")
		return false
	end

	-- Check if it's a custom animation
	local customIndex = table.find(self._customAnimations, name)
	if not customIndex then
		warn("ProceduralAnimator: '" .. name .. "' is not a registered custom animation")
		return false
	end

	-- Remove from custom animations list
	table.remove(self._customAnimations, customIndex)

	-- Remove from animation order
	local orderIndex = table.find(self._animationOrder, name)
	if orderIndex then
		table.remove(self._animationOrder, orderIndex)
	end

	-- Clean up the reference
	if self[name] and type(self[name].Destroy) == "function" then
		self[name]:Destroy()
	end
	self[name] = nil

	return true
end

--[[
	Get the current animation order
	@return table - Array of animation names in order
]]
function ProceduralAnimator.GetAnimationOrder(self : ProceduralAnimator)
	return table.clone(self._animationOrder)
end

--[[
	Set a new animation order
	@param newOrder table - Array of animation names
	@return boolean - Success status
]]
function ProceduralAnimator.SetAnimationOrder(self : ProceduralAnimator, newOrder : {string})
	if not newOrder or type(newOrder) ~= "table" then
		warn("ProceduralAnimator: Animation order must be a table")
		return false
	end

	-- Validate that all animations in newOrder exist
	for _, animName in ipairs(newOrder) do
		if not self[animName] then
			warn("ProceduralAnimator: Animation '" .. animName .. "' does not exist")
			return false
		end
	end

	self._animationOrder = table.clone(newOrder)
	return true
end

--[[
	Update all registered animations
	@param DeltaTime number - Time since last frame
]]
function ProceduralAnimator.Update(self : ProceduralAnimator, DeltaTime : number)
	if not DeltaTime then return false end
	if DeltaTime == 0 or DeltaTime <= 0 then return false end

	-- Update CameraRecoil separately (doesn't apply to viewmodel CFrame)
	self.CameraRecoil:Update(DeltaTime)

	-- Update all animations in order
	for _, animName in ipairs(self._animationOrder) do
		local animation = self[animName]
		if animation and type(animation.Update) == "function" then
			animation:Update(DeltaTime)
		end
	end

	-- Build the combined CFrame
	local ProceduralCF = CFrame.new()

	for _, animName in ipairs(self._animationOrder) do
		local animation = self[animName]
		if animation and type(animation.GetCFrame) == "function" then
			ProceduralCF *= animation:GetCFrame()
		end
	end

	self.CurrentCFrame = ProceduralCF
end

--[[
	Reset all registered animations
]]
function ProceduralAnimator.Reset(self : ProceduralAnimator)
	self.CameraRecoil:Reset()

	for _, animName in ipairs(self._animationOrder) do
		local animation = self[animName]
		if animation and type(animation.Reset) == "function" then
			animation:Reset()
		end
	end
end

--[[
	Get the combined CFrame from all animations
	@return CFrame
]]
function ProceduralAnimator.GetCFrame(self : ProceduralAnimator)
	return self.CurrentCFrame
end

--[[
	Get a specific animation by name
	@param name string - Name of the animation
	@return any - The animation instance or nil
]]
function ProceduralAnimator.GetAnimation(self : ProceduralAnimator, name : string)
	return self[name]
end

--[[
	Check if an animation is registered
	@param name string - Name of the animation
	@return boolean
]]
function ProceduralAnimator.HasAnimation(self : ProceduralAnimator, name : string)
	return self[name] ~= nil
end

local module = {}

--[[
	Create a new ProceduralAnimator instance
	@return ProceduralAnimator
]]
function module.new() : ProceduralAnimator
	local ProceduralAnimator = table.clone(ProceduralAnimator) :: ProceduralAnimator

	-- Initialize default animations
	ProceduralAnimator.WeaponRecoil = WeaponRecoil.new()
	ProceduralAnimator.CameraRecoil = CameraRecoil.new()
	ProceduralAnimator.MouseSway = MouseSway.new()
	ProceduralAnimator.ProceduralSway = ProceduralSway.new()
	ProceduralAnimator.RotationalSway = RotationalSway.new()
	ProceduralAnimator.SpringSway = SpringSway.new()
	ProceduralAnimator.WeaponTilt = WeaponTilt.new()
	ProceduralAnimator.WalkTilt = WalkTilt.new()
	ProceduralAnimator.WalkBob = WalkBob.new()

	-- Initialize custom animations list and order
	ProceduralAnimator._customAnimations = {}
	ProceduralAnimator._animationOrder = {
		"WeaponRecoil",
		"MouseSway",
		"RotationalSway",
		"SpringSway",
		"WeaponTilt",
		"WalkBob",
		"WalkTilt"
	}

	ProceduralAnimator.CurrentCFrame = CFrame.new()

	return ProceduralAnimator :: ProceduralAnimator
end

export type ProceduralAnimator = typeof(ProceduralAnimator)

return table.freeze(module)