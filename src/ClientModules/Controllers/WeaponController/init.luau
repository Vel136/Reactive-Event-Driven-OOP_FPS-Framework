-- WeaponController.lua
-- Handles weapon switching, input binding, and viewmodel management

local module = {}

-- Services
local RunService = game:GetService('RunService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- Shared Modules
local Utilities = ReplicatedStorage.SharedModules.Utilities
local Cores = ReplicatedStorage.SharedModules.Cores
local Configs = ReplicatedStorage.SharedModules.WeaponConfigs

-- Required Modules
local InputController = require(ReplicatedStorage.ClientModules.Controllers.InputController)
local WeaponInstance = require(Cores.WeaponInstance)
local Weapons = require(Configs.Weapons)

local Janitor = require(Utilities.Janitor)
local t = require(Utilities.TypeCheck)
local Promise = require(Utilities.Promise)
local LogService = require(Utilities.LogService)
local Observer = require(Utilities.Observer)
local Data = require(script.Data)
local Signal = require(Utilities.Signal)
-- Weapon Effects
local WeaponSounds = require(ReplicatedStorage.ClientModules.Controllers.WeaponSounds)
-- Procedural Animations
local ProcedularAnimations = script.ProcedularAnimations
local WeaponSway = require(ProcedularAnimations.WeaponSway)
-- Workspace References
local Camera = workspace.CurrentCamera
local Player = game.Players.LocalPlayer
local Mouse = Player:GetMouse()

-- Constants
local SCRIPT_NAME = "WeaponController"
local VIEWMODEL_UPDATE_TIMEOUT = 5

-- Janitor for cleanup management
local mainJanitor = Janitor.new()
local weaponJanitor = Janitor.new()

local cachedCharacter = nil
local cachedHumanoid = nil

-- Cache character/humanoid
local function updateCharacterCache()
	cachedCharacter = Player.Character
	if cachedCharacter then
		cachedHumanoid = cachedCharacter:FindFirstChild("Humanoid")
	end
end

Player.CharacterAdded:Connect(updateCharacterCache)
updateCharacterCache()

local function updateViewmodel(dt)
	if not Data.CurrentViewmodel or not cachedHumanoid then return end
	if not Data.CurrentViewmodel.Parent or not Data.CurrentViewmodel.PrimaryPart then
		Data.CurrentViewmodel = nil
		return
	end

	WeaponSway.WalkTilt.Update(cachedHumanoid, Camera.CFrame)
	WeaponSway.MouseSway.Update()
	WeaponSway.CameraRotationSway.Update(Camera.CFrame)
	WeaponSway.CameraKick.Update(dt)
	local weapon = Weapons(Data.CurrentWeapon)
	
	
	if weapon:IsAiming() then
		local aimName = weapon.Data.AimAttachment
			if aimName then
			local aimPart = Data.CurrentViewmodel:FindFirstChild(aimName, true)
			if aimPart then
				WeaponSway.AimingSway.UpdateAiming(Data.CurrentViewmodel,aimPart,dt)
			end
		end
	else
		WeaponSway.AimingSway.UpdateIdle(dt)
	end
	

	Data.CurrentViewmodel.PrimaryPart.CFrame = Camera.CFrame * 
		WeaponSway.WalkTilt.GetTilt() *
		WeaponSway.AimingSway.GetAimCF() *
		WeaponSway.CameraRotationSway.GetSway() *
		WeaponSway.MouseSway.GetCombinedSway() *
		WeaponSway.CameraKick.GetKick()

	local muzzle = Data.CurrentViewmodel:FindFirstChild(weapon.Data.BarrelAttachment)
	if muzzle and muzzle:IsA("Attachment") then
		Data.CurrentPosition = muzzle.WorldPosition
	end
end

local function cleanupCurrentWeapon()
	weaponJanitor:Cleanup()

	if Data.CurrentWeapon then
		local existingModel = Camera:FindFirstChild(Data.CurrentWeapon)
		if existingModel then
			existingModel.Parent = ReplicatedStorage.Assets.Viewmodels
		end

		local existingWeapon = Weapons(Data.CurrentWeapon)
		if existingWeapon then
			pcall(function() existingWeapon:Unequip() end)
		end
	end

	Data.CurrentWeapon = nil
	Data.CurrentViewmodel = nil
	Data.CurrentPosition = nil
end

-- Equip weapon (returns Promise only because of potential async loading)
local function equipNewWeapon(weaponName)
	return Promise.new(function(resolve, reject)
		local gunData = Weapons(weaponName)
		if not gunData or not gunData.Data.Model then
			reject("Invalid weapon: " .. tostring(weaponName))
			return
		end

		
		
		WeaponSounds.BindWeaponSound(gunData)
		gunData:Equip()
		
		local model : Model = gunData.Data.Model
		model.Parent = Camera
		Data.CurrentWeapon = weaponName
		Data.CurrentViewmodel = model
		
		weaponJanitor:Add(gunData.Signals.OnShoot:Connect(function()
			WeaponSway.CameraKick.Kick(1)
		end),"Disconnect")
		LogService.Print("Equipped: " .. weaponName, SCRIPT_NAME)
		resolve()
	end):catch()
end

function module.Init()
	InputController.Init()

	-- Fire handler
	mainJanitor:Add(InputController.Signals.Fire:Connect(function(isFiring)
		if not isFiring or not Data.CurrentWeapon then return end

		local weapon = Weapons(Data.CurrentWeapon)
		if not weapon or not Data.CurrentPosition then return end

		local origin = Data.CurrentPosition
		local direction = (Mouse.Hit.Position - origin).Unit
		
		weapon:Fire(origin, direction)
	end),"Disconnect")
	
	-- Reload handler
	mainJanitor:Add(InputController.Signals.Reload:Connect(function()
		local weapon = Weapons(Data.CurrentWeapon)
		if not weapon then return end

		weapon:Reload()
	end),"Disconnect")

	-- Aim handler
	mainJanitor:Add(InputController.Signals.Aim:Connect(function(isAiming)
		if not Data.CurrentViewmodel then return end

		local weapon = Weapons(Data.CurrentWeapon)
		weapon:SetAiming(isAiming)
	end),"Disconnect")

	-- Viewmodel update
	mainJanitor:Add(RunService.RenderStepped:Connect(updateViewmodel))

	LogService.Print("WeaponController initialized", SCRIPT_NAME)
end

local lastswitch = os.clock()

function module.SwitchWeapon(weaponName)
	if os.clock() - lastswitch < .2 then
		return false 
	end
	
	lastswitch = os.clock()
	if not weaponName then
		cleanupCurrentWeapon()
		WeaponSway.WalkTilt.Reset()
		WeaponSway.MouseSway.Reset()
		WeaponSway.AimingSway.Reset()
		WeaponSway.CameraRotationSway.Reset()
		WeaponSway.CameraKick.Reset()
		WeaponSounds.UnbindWeaponSound()
		return Promise.resolve()
	end

	if Data.CurrentWeapon == weaponName then
		return Promise.reject("Already equipped")
	end

	cleanupCurrentWeapon()
	return equipNewWeapon(weaponName)
end

function module.Cleanup()
	mainJanitor:Cleanup()
	weaponJanitor:Cleanup()
	WeaponSway:Stop()
end

return module