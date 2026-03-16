--!native
--!optimize 2

-- WeaponManager.lua
--[[
	Client-side weapon orchestrator.
	- Bridges GunInputManager signals to the active weapon
	- Manages viewmodel positioning and procedural animation
	- Handles equip/unequip lifecycle
]]

local Identity = "WeaponManager"

-- ─── Services ────────────────────────────────────────────────────────────────

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities     = ReplicatedStorage.Shared.Modules.Utilities
local WeaponFolder  = ReplicatedStorage.Client.Modules.FPSSystem.GunSystem

local Camera = workspace.CurrentCamera
local Player = Players.LocalPlayer

-- ─── Modules ─────────────────────────────────────────────────────────────────

local GunInputManager         = require(ReplicatedStorage.Client.Modules.FPSSystem.Controllers.GunInputManager)
local GunManager           = require(WeaponFolder.GunManager)
local WeaponConfiguration  = require(ReplicatedStorage.Client.Modules.FPSSystem.Configuration.Guns)
local Data                 = require(script.Data)

local Janitor    = require(Utilities.Janitor)
local Promise    = require(Utilities.Promise)
local LogService = require(Utilities.Logger)

local Logger = LogService.new(Identity, false)
-- ─── Module ──────────────────────────────────────────────────────────────────

local WeaponManager   = {}
WeaponManager.__index = WeaponManager
WeaponManager.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

local MainJanitor  = Janitor.new()
local WeaponJanitor = Janitor.new()

local CachedCharacter : Model?    = nil
local CachedHumanoid  : Humanoid? = nil

-- ─── Internal: character tracking ────────────────────────────────────────────

local function UpdateCharacterCache()
	CachedCharacter = Player.Character
	if not CachedCharacter then return end

	CachedHumanoid = CachedCharacter:FindFirstChild("Humanoid") :: Humanoid?
	if not CachedHumanoid then return end

	CachedHumanoid.Running:Connect(function(speed: number)
		local weapon = WeaponConfiguration[Data.CurrentWeapon]
		if not weapon or not weapon.ProceduralAnimator then return end

		if speed > 0.1 then
			weapon.ProceduralAnimator.WalkBob:SetMoving(true, speed)
		else
			weapon.ProceduralAnimator.WalkBob:SetMoving(false, speed)
		end
	end)
end

Player.CharacterAdded:Connect(UpdateCharacterCache)
UpdateCharacterCache()

-- ─── Internal: viewmodel ─────────────────────────────────────────────────────

local function UpdateViewmodel(deltaTime: number)
	if not Data.CurrentViewmodel or not CachedHumanoid then return end
	if not Data.CurrentViewmodel.Parent or not Data.CurrentViewmodel.PrimaryPart then
		Data.CurrentViewmodel = nil
		return
	end

	local weapon = WeaponConfiguration[Data.CurrentWeapon]
	if not weapon then return end

	-- Procedural animation
	if weapon.ProceduralAnimator then
		weapon.ProceduralAnimator:Update(deltaTime)

		local aimPart = weapon.Data.AimAttachment
		if aimPart then
			if weapon:IsAiming() then
				if aimPart:IsA("Attachment") then
					weapon.ProceduralAnimator.ProceduralSway:Update(
						deltaTime,
						Data.CurrentViewmodel.PrimaryPart.CFrame,
						weapon.Data.AimAttachment.WorldCFrame
					)
				elseif type(aimPart) == "string" then
					aimPart = Data.CurrentViewmodel:FindFirstChild(weapon.Data.BarrelAttachment)
					weapon.ProceduralAnimator.ProceduralSway:Update(
						deltaTime,
						Data.CurrentViewmodel.PrimaryPart.CFrame,
						weapon.Data.AimAttachment.WorldCFrame
					)
				elseif typeof(aimPart) == "Instance" then
					weapon.ProceduralAnimator.ProceduralSway:Update(
						deltaTime,
						Data.CurrentViewmodel.PrimaryPart.CFrame,
						weapon.Data.AimAttachment.CFrame
					)
				end
			else
				weapon.ProceduralAnimator.ProceduralSway:Update(deltaTime)
			end
		end

		weapon.ProceduralAnimator.WalkTilt:Update(CachedHumanoid, Camera.CFrame)
	end

	-- Apply final viewmodel CFrame
	local aimCF        = weapon.ProceduralAnimator.ProceduralSway:GetCFrame()
	local proceduralCF = weapon.ProceduralAnimator and weapon.ProceduralAnimator:GetCFrame() or CFrame.new()
	Data.CurrentViewmodel.PrimaryPart.CFrame = Camera.CFrame * proceduralCF * aimCF

	-- Update muzzle position and direction
	local muzzle = weapon.Data.BarrelAttachment
	if muzzle then
		if muzzle:IsA("Attachment") then
			Data.CurrentPosition  = muzzle.WorldPosition
			Data.CurrentDirection = muzzle.WorldCFrame.LookVector
		elseif type(muzzle) == "string" then
			muzzle = Data.CurrentViewmodel:FindFirstChild(weapon.Data.BarrelAttachment)
			if muzzle then
				Data.CurrentPosition  = muzzle.WorldPosition
				Data.CurrentDirection = muzzle.WorldCFrame.LookVector
			end
		elseif typeof(muzzle) == "Instance" then
			Data.CurrentPosition  = muzzle.Position
			Data.CurrentDirection = muzzle.LookVector
		end
	end
end

-- ─── Weapon lifecycle ────────────────────────────────────────────────────────

--- Unequips the current weapon and clears all state.
function WeaponManager.CleanUp(self: WeaponManager)
	WeaponJanitor:Cleanup()

	if Data.CurrentWeapon then
		local existingModel = Camera:FindFirstChild(Data.CurrentWeapon)
		if existingModel then
			existingModel.Parent = ReplicatedStorage.Assets.Viewmodels
		end

		local existingWeapon = WeaponConfiguration[Data.CurrentWeapon]
		if existingWeapon then
			pcall(function()
				existingWeapon:Unequip()
			end)
		end
	end

	Data.CurrentWeapon     = nil
	Data.CurrentViewmodel  = nil
	Data.CurrentPosition   = nil
	Data.CurrentDirection  = nil
end

--- Equips the named weapon. Returns a Promise that resolves when complete.
function WeaponManager.EquipWeapon(self: WeaponManager, weaponName: string): any
	return Promise.new(function(resolve, reject)
		local weapon = WeaponConfiguration[weaponName]
		if not weapon or not weapon.Data.Model then
			reject("EquipWeapon: invalid weapon '" .. tostring(weaponName) .. "'")
			return
		end

		weapon:Equip()

		local model = weapon.Data.Model
		model.Parent          = Camera
		Data.CurrentWeapon    = weaponName
		Data.CurrentViewmodel = model

		MainJanitor:Add(weapon.Signals.OnFire:Connect(function()
			if not weapon.ProceduralAnimator then return end
			if weapon.ProceduralAnimator.WeaponRecoil then
				weapon.ProceduralAnimator.WeaponRecoil:Apply()
			end
			if weapon.ProceduralAnimator.CameraRecoil then
				weapon.ProceduralAnimator.CameraRecoil:Apply()
			end
		end), "Disconnect")

		Logger:Print(string.format("EquipWeapon: equipped '%s'", weaponName))
		resolve()
	end):catch()
end

--- Unequips the current weapon and equips a new one. Pass nil to just unequip.
function WeaponManager.SwitchWeapon(self: WeaponManager, weaponName: string?): any
	if not weaponName then
		self:CleanUp()
		return Promise.resolve()
	end

	if Data.CurrentWeapon == weaponName then
		return Promise.reject("SwitchWeapon: already equipped")
	end

	self:CleanUp()
	return self:EquipWeapon(weaponName)
end

-- ─── Initialization ──────────────────────────────────────────────────────────

--- Wires all input signals and starts the render loop.
function WeaponManager._Initialize(self: WeaponManager)
	-- Fire
	GunInputManager.Signals.FirePulse:Connect(function()
		if not Data.CurrentWeapon or not Data.CurrentPosition then return end

		local weapon = WeaponConfiguration[Data.CurrentWeapon]
		if not weapon or not weapon:IsEquipped() then return end

		weapon:Fire(Data.CurrentPosition, Data.CurrentDirection)
	end)

	-- Reload
	GunInputManager.Signals.Reloaded:Connect(function()
		local weapon = WeaponConfiguration[Data.CurrentWeapon]
		if not weapon then return end
		weapon:Reload()
	end)

	-- Aim
	GunInputManager.Signals.AimStarted:Connect(function()
		if not Data.CurrentViewmodel then return end
		local weapon = WeaponConfiguration[Data.CurrentWeapon]
		if weapon then weapon:SetAiming(true) end
	end)
	
	GunInputManager.Signals.AimStopped:Connect(function()
		if not Data.CurrentViewmodel then return end
		local weapon = WeaponConfiguration[Data.CurrentWeapon]
		if weapon then weapon:SetAiming(false) end
	end)

	-- Viewmodel update loop
	RunService.RenderStepped:Connect(function(deltaTime: number)
		UpdateViewmodel(deltaTime)
	end)

	Logger:Print("_Initialize: WeaponManager ready")
end

-- ─── Singleton ───────────────────────────────────────────────────────────────

local _instance: WeaponManager

local function GetInstance(): WeaponManager
	if not _instance then
		_instance = setmetatable({}, WeaponManager) :: WeaponManager
		_instance:_Initialize()
	end
	return _instance
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type WeaponManager = typeof(setmetatable({}, WeaponManager))

return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("WeaponManager is read-only")
	end,
})

