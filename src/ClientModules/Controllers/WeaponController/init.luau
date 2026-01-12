--!native
--!optimize 2

local module = {}
module.__index = module

-- Services
local RunService = game:GetService('RunService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- Module Paths
local Utilities = ReplicatedStorage.SharedModules.Utilities
local Cores = ReplicatedStorage.ClientModules.Cores
local Configs = ReplicatedStorage.SharedModules.WeaponConfigs

-- Required Modules
local InputController = require(ReplicatedStorage.ClientModules.Controllers.InputController)
local WeaponInstance = require(Cores.WeaponInstance)
local Weapons = require(Configs.Weapons)
local Janitor = require(Utilities.Janitor)
local Promise = require(Utilities.Promise)
local LogService = require(Utilities.LogService)
local Data = require(script.Data)

-- Procedural Animations
local ProcedularAnimations = require(script.ProcedularAnimations)

-- References
local Camera = workspace.CurrentCamera
local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()

-- Constants
local Identity = "[WeaponController]"

-- Janitors
local MainJanitor = Janitor.new()
local WeaponJanitor = Janitor.new()

-- Cached references
local CachedCharacter = nil
local CachedHumanoid = nil

-- Update character cache
local function UpdateCharacterCache()
	CachedCharacter = Player.Character
	if CachedCharacter then
		CachedHumanoid = CachedCharacter:FindFirstChild("Humanoid")
		
		CachedHumanoid.Running:Connect(function(Speed)
			if Speed > 0.1 then
				ProcedularAnimations.WalkBob.SetMoving(true,Speed)
			else
				ProcedularAnimations.WalkBob.SetMoving(false)
			end
		end)
	end
end

Player.CharacterAdded:Connect(UpdateCharacterCache)
UpdateCharacterCache()

-- Update viewmodel position and apply sway
function module:UpdateViewmodel(DeltaTime)
	if not Data.CurrentViewmodel or not CachedHumanoid then return end
	if not Data.CurrentViewmodel.Parent or not Data.CurrentViewmodel.PrimaryPart then
		Data.CurrentViewmodel = nil
		return
	end

	local Weapon = Weapons.GetWeaponInstance(Data.CurrentWeapon)

	-- Update sway systems
	ProcedularAnimations.WalkTilt.Update(CachedHumanoid, Camera.CFrame)
	ProcedularAnimations.MouseSway.Update()
	ProcedularAnimations.RotationalSway.Update(Camera.CFrame)
	ProcedularAnimations.CameraRecoil.Update(DeltaTime)
	ProcedularAnimations.WeaponRecoil.Update(DeltaTime)
	ProcedularAnimations.SprintTilt.Update(DeltaTime)
	ProcedularAnimations.WalkBob.Update(DeltaTime)
	ProcedularAnimations.SpringSway.Update(DeltaTime)
	-- Handle aiming
	if Weapon:IsAiming() then
		local AimAttachment : Attachment = Weapon.Data.AimAttachment
		if AimAttachment then
			ProcedularAnimations.ProceduralSway.UpdateAiming(
				Data.CurrentViewmodel.PrimaryPart.CFrame,
				AimAttachment.WorldCFrame,
				DeltaTime
			)
		end
	else
		ProcedularAnimations.ProceduralSway.UpdateIdle(DeltaTime)
	end
	
	-- Apply all sway to viewmodel
	Data.CurrentViewmodel.PrimaryPart.CFrame = Camera.CFrame * 
		ProcedularAnimations.WalkTilt.GetTilt() *
		ProcedularAnimations.ProceduralSway.GetAimCF() *
		ProcedularAnimations.RotationalSway.GetSway() *
		ProcedularAnimations.MouseSway.GetCombinedSway() *
		ProcedularAnimations.WeaponRecoil.GetKick() * 
		ProcedularAnimations.SprintTilt.GetCFrame() *
		ProcedularAnimations.WalkBob.GetCFrame() *
		ProcedularAnimations.SpringSway.GetCFrame()

	
	local Muzzle = Weapon.Data.BarrelAttachment
	if Muzzle and Muzzle:IsA("Attachment") then
		Data.CurrentPosition = Muzzle.WorldPosition
	elseif Muzzle and type(Muzzle) == "string" then
		Muzzle = Data.CurrentViewmodel:FindFirstChild(Weapon.Data.BarrelAttachment)
		Data.CurrentPosition = Muzzle.WorldPosition
	end
end

-- Clean up current weapon
function module:CleanUp()
	WeaponJanitor:Cleanup()

	if Data.CurrentWeapon then
		local ExistingModel = Camera:FindFirstChild(Data.CurrentWeapon)
		if ExistingModel then
			ExistingModel.Parent = ReplicatedStorage.Assets.Viewmodels
		end

		local ExistingWeapon = Weapons.GetWeaponInstance(Data.CurrentWeapon)
		if ExistingWeapon then
			pcall(function() 
				ExistingWeapon:Unequip() 
			end)
		end
	end

	Data.CurrentWeapon = nil
	Data.CurrentViewmodel = nil
	Data.CurrentPosition = nil -- Clear cached position on cleanup
end

-- Equip weapon
function module:EquipWeapon(WeaponName)
	return Promise.new(function(Resolve, Reject)
		local WeaponInstance = Weapons.GetWeaponInstance(WeaponName)
		if not WeaponInstance or not WeaponInstance.Data.Model then
			Reject("Invalid weapon: " .. tostring(WeaponName))
			return
		end

		WeaponInstance:Equip()

		local Model = WeaponInstance.Data.Model
		Model.Parent = Camera
		Data.CurrentWeapon = WeaponName
		Data.CurrentViewmodel = Model

		local GunKick = WeaponInstance.Data.GunKick
		local GunSway = WeaponInstance.Data.Sway

		local function ReupdateGun(Aiming)
			-- Adapt Viewmodel Kick
			local KickConfiguration = Aiming and GunKick.Aiming or GunKick.Base or {}
			ProcedularAnimations.WeaponRecoil.SetConfig(KickConfiguration)

			-- Adapt Viewmodel Sway, Idle Time, Aim Time
			local SwayConfiguration = Aiming and GunSway.Aiming or GunSway.Base or {}
			SwayConfiguration.AimTime = WeaponInstance.Data.AimTime or .3
			SwayConfiguration.IdleTime = WeaponInstance.Data.IdleTime or .3

			ProcedularAnimations.ProceduralSway.SetConfig(SwayConfiguration)
		end
		ReupdateGun()
		WeaponJanitor:Add(WeaponInstance.Signals.OnAimChanged:Connect(function(Aiming)
			ReupdateGun(Aiming)
		end), "Disconnect")

		-- Connect fire event
		WeaponJanitor:Add(WeaponInstance.Signals.OnFire:Connect(function()
			ProcedularAnimations.CameraRecoil.ApplyRecoil()

			local KickParams = WeaponInstance.Data.GunKick
			if KickParams then
				ProcedularAnimations.WeaponRecoil.Kick()
			else
				ProcedularAnimations.WeaponRecoil.Kick()
			end
		end), "Disconnect")

		LogService.Print("Equipped: " .. WeaponName, Identity)
		Resolve()
	end):catch()
end

-- Initialize controller
function module:Initialize()
	-- Fire handler
	MainJanitor:Add(InputController.Signals.Fire:Connect(function(IsFiring)
		if not IsFiring or not Data.CurrentWeapon then return end

		local Weapon = Weapons.GetWeaponInstance(Data.CurrentWeapon)
		if not Weapon or not Data.CurrentPosition then return end

		-- Use cached position instead of reading Muzzle.WorldPosition directly
		-- This ensures we always use the position from the most recent RenderStepped update
		local Origin = Data.CurrentPosition
		local Direction = (Mouse.Hit.Position - Origin).Unit

		Weapon:Fire(Origin, Direction)
	end), "Disconnect")
	
	-- Sprint Handler
	MainJanitor:Add(InputController.Signals.Sprint:Connect(function(sprinting)
		ProcedularAnimations.SprintTilt.SetSprinting(sprinting)
		CachedHumanoid.WalkSpeed = sprinting and 32 or 16
	end),"Disconnect")
	
	print("INITIALIZED")
	-- Reload handler
	MainJanitor:Add(InputController.Signals.Reload:Connect(function()
		local Weapon = Weapons.GetWeaponInstance(Data.CurrentWeapon)
		if not Weapon then return end

		Weapon:Reload()
	end), "Disconnect")

	-- Aim handler
	MainJanitor:Add(InputController.Signals.Aim:Connect(function(IsAiming)
		if not Data.CurrentViewmodel then return end

		local Weapon = Weapons.GetWeaponInstance(Data.CurrentWeapon)
		Weapon:SetAiming(IsAiming)
	end), "Disconnect")

	-- Viewmodel update loop - runs every frame to keep cached position fresh
	MainJanitor:Add(RunService.RenderStepped:Connect(function(DeltaTime)
		module:UpdateViewmodel(DeltaTime)
	end))

	LogService.Print("WeaponController initialized", Identity)
end

-- Switch weapon
function module.SwitchWeapon(WeaponName)
	if not WeaponName then
		module:CleanUp()
		ProcedularAnimations.WalkTilt.Reset()
		ProcedularAnimations.MouseSway.Reset()
		ProcedularAnimations.ProceduralSway.Reset()
		ProcedularAnimations.MouseSway.Reset()

		return Promise.resolve()
	end

	if Data.CurrentWeapon == WeaponName then
		return Promise.reject("Already equipped")
	end

	module:CleanUp()
	return module:EquipWeapon(WeaponName)
end

-- Singleton instance
local Instance

local function GetInstance()
	if not Instance then
		Instance = setmetatable({}, module)
		Instance:Initialize()
	end
	return Instance
end

return setmetatable({}, {
	__index = function(_, Key)
		return GetInstance()[Key]
	end,
	__newindex = function()
		error("Cannot modify singleton service", Identity)
	end
})