-- BodyAnimator.lua
local Identity = "BodyAnimator"
local BodyAnimator = {}
BodyAnimator.__type = Identity

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- References
local LocalPlayer = Players.LocalPlayer
local Utilities = ReplicatedStorage.Shared.Modules.Utilities
local AnimationSystem = ReplicatedStorage.Client.Modules.FPSSystem.AnimationSystem

-- Animation Assets
local Animations = ReplicatedStorage.Assets.Animations
local CharacterAnimations = Animations.Character
local InActiveAnimation : Animation = CharacterAnimations.Inactive_Equip
local IdleAnimation : Animation   = CharacterAnimations.Idle_Equip
local ActiveAnimation : Animation     = CharacterAnimations.Active_Equip

-- Animation Identifiers
local ANIM_EQUIP   = "Equip"
local ANIM_IDLE    = "Idle"
local ANIM_UNEQUIP = "Unequip"

-- Modules
local AnimationController = require(AnimationSystem.AnimationController)
local GunEquipAnimator    = require(script.Parent.GunEquipReplicator)

-- Additional Modules
local LogService = require(Utilities.Logger)
local Logger     = LogService.new(Identity, false)

-- Internal: Per-character controller cache
-- [Player] = AnimationController
local Controllers: {[Player]: any} = {}

--[[
	Internal: Gets or creates an AnimationController for a character.
	Also loads all body animations onto it if freshly created.
]]
local function GetController(Player: Player): any?
	Logger:Print("GetController called for: " .. Player.Name, Identity)

	if Controllers[Player] then
		Logger:Print("Returning cached controller for: " .. Player.Name, Identity)
		return Controllers[Player]
	end

	Logger:Print("No cached controller found, creating new one for: " .. Player.Name, Identity)

	local Character = Player.Character
	if not Character then
		Logger:Warn("No character found for player: " .. Player.Name, Identity)
		return nil
	end

	Logger:Print("Character found: " .. Character.Name .. " | Creating AnimationController", Identity)

	local Controller = AnimationController.new(Character)
	if not Controller then
		Logger:Warn("Failed to create AnimationController for: " .. Player.Name, Identity)
		return nil
	end

	Logger:Print("AnimationController created successfully for: " .. Player.Name .. " | Loading animations", Identity)

	-- Load all body animations upfront
	Controller:LoadAnimations(
		{
			[ANIM_EQUIP]   = ActiveAnimation,
			[ANIM_IDLE]    = IdleAnimation,
			[ANIM_UNEQUIP] = InActiveAnimation,
		},
		{
			[ANIM_EQUIP]   = Enum.AnimationPriority.Action,
			[ANIM_IDLE]    = Enum.AnimationPriority.Idle,
			[ANIM_UNEQUIP] = Enum.AnimationPriority.Action,
		},
		{
			[ANIM_EQUIP]   = false,
			[ANIM_IDLE]    = true,
			[ANIM_UNEQUIP] = false,
		}
	)

	Logger:Print("Animations loaded for: " .. Player.Name .. " | Caching controller", Identity)

	Controllers[Player] = Controller

	-- Clean up when the character is removed / player leaves
	Player.CharacterRemoving:Connect(function()
		Logger:Print("CharacterRemoving fired for: " .. Player.Name .. " | Cleaning up controller", Identity)
		if Controllers[Player] then
			Controllers[Player]:Destroy()
			Controllers[Player] = nil
			Logger:Print("Controller destroyed and removed from cache for: " .. Player.Name, Identity)
		else
			Logger:Warn("CharacterRemoving: No controller found in cache for: " .. Player.Name, Identity)
		end
	end)

	return Controller
end

--[[
	Internal: Play Equip → wait for it to finish → transition to Idle
]]
local function PlayEquipSequence(Controller: AnimationController.AnimationHandler)
	Logger:Print("PlayEquipSequence started | Stopping all animations with fade 0.15", Identity)
	Controller:StopAllAnimations(0.15)

	Logger:Print("Playing EQUIP animation", Identity)
	local EquipTrack = Controller:PlayAnimation(ANIM_EQUIP, 0.2)
	if not EquipTrack then
		Logger:Warn("PlayEquipSequence: EquipTrack is nil, aborting sequence", Identity)
		return
	end

	Logger:Print("EquipTrack playing | Length: " .. tostring(EquipTrack.Length) .. "s | Waiting for Stopped", Identity)
	EquipTrack.Stopped:Wait()

	local CurrentState = Controller:GetCurrentState()
	Logger:Print("EquipTrack stopped | CurrentState: " .. tostring(CurrentState), Identity)

	if CurrentState == ANIM_EQUIP then
		Logger:Print("State is still EQUIP, transitioning to IDLE", Identity)
		Controller:PlayAnimation(ANIM_IDLE, 0.3)
	else
		Logger:Warn("State changed during equip sequence (got: " .. tostring(CurrentState) .. "), skipping idle transition", Identity)
	end
end

--[[
	Internal: Stop Idle → play Unequip
]]
local function PlayUnequipSequence(Controller: any)
	Logger:Print("PlayUnequipSequence started | Fading out IDLE (0.2) and playing UNEQUIP (0.2)", Identity)
	Controller:StopAnimation(ANIM_IDLE, 0.2)
	local UnequipTrack = Controller:PlayAnimation(ANIM_UNEQUIP, 0.2)
	if not UnequipTrack then
		Logger:Warn("PlayUnequipSequence: UnequipTrack is nil", Identity)
	else
		Logger:Print("UnequipTrack playing | Length: " .. tostring(UnequipTrack.Length) .. "s", Identity)
	end
end

function BodyAnimator._Initialize()
	Logger:Print("Initializing BodyAnimator | Connecting signals", Identity)

	-- Equip
	GunEquipAnimator.Signals.OnWeaponEquipped:ConnectAsync(function(Player: Player, _GunModel: Model, _GunInstanceId: string?)
		Logger:Print("OnWeaponEquipped fired | Player: " .. Player.Name .. " | GunInstanceId: " .. tostring(_GunInstanceId), Identity)
		local Controller = GetController(Player)
		if not Controller then
			Logger:Warn("OnWeaponEquipped: Could not get controller for: " .. Player.Name .. ", aborting", Identity)
			return
		end
		PlayEquipSequence(Controller)
	end)

	-- Unequip
	GunEquipAnimator.Signals.OnWeaponUnequipped:ConnectAsync(function(Player: Player, _GunInstanceId: string?)
		Logger:Print("OnWeaponUnequipped fired | Player: " .. Player.Name .. " | GunInstanceId: " .. tostring(_GunInstanceId), Identity)
		local Controller = GetController(Player)
		if not Controller then
			Logger:Warn("OnWeaponUnequipped: Could not get controller for: " .. Player.Name .. ", aborting", Identity)
			return
		end
		PlayUnequipSequence(Controller)
	end)

	Logger:Print("BodyAnimator signals connected successfully", Identity)
end

-- Singleton Pattern
local metatable = {__index = BodyAnimator}
local instance

export type BodyAnimator = typeof(setmetatable({}, metatable))

local function GetInstance()
	if not instance then
		Logger:Print("No existing instance found, creating singleton", Identity)
		instance = setmetatable({}, metatable)
		instance._Initialize()
		Logger:Print("Singleton created and initialized", Identity)
	else
		Logger:Print("Returning existing singleton instance", Identity)
	end
	return instance
end

-- Export as singleton with read-only access
return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify BodyAnimator singleton", 2)
	end,
}) :: BodyAnimator