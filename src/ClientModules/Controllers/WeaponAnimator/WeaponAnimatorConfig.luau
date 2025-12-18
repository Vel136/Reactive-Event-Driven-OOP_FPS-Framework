
-- WeaponAnimatorConfig.lua
--[[
	Configuration module for WeaponAnimator
	Contains all enums, constants, and settings
]]

-- Animation enum (numeric for better performance)
local Animations = {
	Idle = 1,
	Aim = 2,
	Fire = 3,
	Equip = 4,
	Reload = 5,
}

local AnimatorConfig = {
	-- Export enum for external use
	Animations = Animations,

	-- Animation state priorities (higher = more important)
	Priority = {
		[Animations.Idle] = 1,
		[Animations.Aim] = 2,
		[Animations.Fire] = 3,
		[Animations.Equip] = 4,
		[Animations.Reload] = 5,
	},

	-- Animation fade times (in seconds)
	FadeTime = {
		Instant = 0,
		Fast = 0.1,
		Normal = 0.2,
		Slow = 0.3,
	},

	-- Animation states enum (maps numeric enum to string names)
	States = {
		[Animations.Idle] = "Idle",
		[Animations.Aim] = "Aim",
		[Animations.Fire] = "Fire",
		[Animations.Equip] = "Equip",
		[Animations.Reload] = "Reload",
	},

	-- Roblox animation priority mapping
	RobloxPriority = {
		[Animations.Idle] = Enum.AnimationPriority.Idle,
		[Animations.Aim] = Enum.AnimationPriority.Action,
		[Animations.Fire] = Enum.AnimationPriority.Action,
		[Animations.Equip] = Enum.AnimationPriority.Action3,
		[Animations.Reload] = Enum.AnimationPriority.Action4,
	},

	-- Animation loop settings
	LoopSettings = {
		[Animations.Idle] = true,
		[Animations.Aim] = true,
		[Animations.Fire] = false,
		[Animations.Equip] = false,
		[Animations.Reload] = false,
	},

	-- Transition rules: Which animations can interrupt others
	-- Key = animation that wants to play, Value = array of animations it can interrupt
	TransitionRules = {
		-- Reload can interrupt everything
		[Animations.Reload] = {
			Animations.Idle, 
			Animations.Aim, 
			Animations.Fire, 
			Animations.Equip
		},

		-- Equip can interrupt everything except reload
		[Animations.Equip] = {
			Animations.Idle, 
			Animations.Aim, 
			Animations.Fire
		},

		-- Fire can play alongside Aim (only stops Idle)
		[Animations.Fire] = {
			Animations.Idle
		},

		-- Aim can interrupt Idle
		[Animations.Aim] = {
			Animations.Idle
		},

		-- Idle doesn't interrupt anything
		[Animations.Idle] = {},
	},

	-- Debug settings
	Debug = {
		EnableLogging = true,
		LogTransitions = true,
		LogPriorityBlocks = true,
	},
}

return AnimatorConfig
