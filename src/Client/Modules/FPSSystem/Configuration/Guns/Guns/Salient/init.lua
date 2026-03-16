-- Salient.lua (REFACTORED - Using GlobalMovementHandler)

-- Services
local TweenService = game:GetService('TweenService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService("Players")
local Lighting = game:GetService('Lighting')

-- References
local Weapon = ReplicatedStorage.Client.Modules.FPSSystem.GunSystem

-- Required Modules
local ProceduralGunDecorator = require(Weapon.ProceduralGunDecorator)
local GunManager = require(Weapon.GunManager)

local GunInputManager = require(ReplicatedStorage.Client.Modules.FPSSystem.Controllers.GunInputManager)
local SalientData = require(ReplicatedStorage.Shared.Modules.FPSSystem.Configuration.Guns.Salient)

-- Additional Modules
local ObjectCache = require(ReplicatedStorage.Shared.Modules.Utilities.ObjectCache)
local DOFManager = require(ReplicatedStorage.Client.Modules.FPSSystem.Effects.DOFManager)
local CameraShake = require(ReplicatedStorage.Shared.Modules.Utilities.CameraShaker)

local GlobalMovementHandler = require(ReplicatedStorage.Client.Modules.MovementSystem.GlobalMovementHandler)

-- Weapon-specific procedural animation configuration
local ProceduralConfig = require(script.Configuration.ProceduralConfiguration)

-- Constants
local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local DEFAULT_FOV = 90
local ADS_FOV = 55
local TWEEN_DURATION = 0.2
local TRACER_POOL_SIZE = 70

local Sounds = ReplicatedStorage.Assets.Sounds.Salient

-- Module
local module = {}

-- Weapon Initialization
local SalientGun = GunManager.new(SalientData.ID, SalientData)

print("SALIENT GUN INSTANCE",SalientGun)
local Salient = ProceduralGunDecorator.new(SalientGun, {}, {
	Attachment = SalientData.ShellEjectAttachment,
	Bullets = {
		Live = {
			Bullet = workspace.Effects.Bullets:WaitForChild('Salient'):WaitForChild('Salient'),
			AutoEjectShells = SalientData.AutoEjectShells or true,
			Data = {
				EjectRight = 1.2,
				EjectUp = 0.5,
				EjectForward = -0.25,
				BaseSpeed = 18,
				SpeedVariance = 2,
				AngleNoise = math.rad(3),
				AngularVelocity = {
					X = {Min = -12, Max = 12},
					Y = {Min = -20, Max = 20},
					Z = {Min = -12, Max = 12},
				},
				CasingLifetime = 1,
				PoolSize = 30,
				PoolContainer = workspace.Effects.Bullets:WaitForChild('Salient'),
				UseRenderStepped = true,
			}
		}
	}
}) 

-- State tracking
local IsCanting = false
local IsAiming = false
local IsSprinting = false

-- Movement references
local CantingMovement = GlobalMovementHandler:CreateCustomMovement("WeaponCanting", 7, Enum.KeyCode.Z, 10)
CantingMovement:SetHold(false)

-- Initialization
function module._InitializeProceduralAnimations()
	Salient.ProceduralAnimator.CameraRecoil:SetConfig(ProceduralConfig.Recoil.Default.Camera)
	Salient.ProceduralAnimator.WeaponRecoil:SetConfig(ProceduralConfig.Recoil.Default.Weapon)
	Salient.ProceduralAnimator.WalkBob:SetConfig(ProceduralConfig.WalkBob.Default)

	Salient.ProceduralAnimator.ProceduralSway:SetConfig({
		AimTime = SalientData.AimTime or ProceduralConfig.Sway.Default.AimTime,
		SwaySpeed = ProceduralConfig.Sway.Default.SwaySpeed,
		BreathRate = ProceduralConfig.Sway.Default.BreathRate,	
	})

	Salient.ProceduralAnimator.WeaponTilt:SetConfig({
		WeaponTiltX = -20,
		WeaponTiltY = 20,
		WeaponTiltZ = 10,
		WeaponOffsetX = .2,
		WeaponOffsetY = .1,
		WeaponOffsetZ = .1,
	})
end

function module._InitializeMuzzleFlash()
	local MuzzleParticles = SalientData.BarrelAttachment:GetChildren()
	local MuzzleLight = SalientData.BarrelAttachment.Light

	local FlashHandler = GunManager.Features.MuzzleFlashController.new({
		Name = "SalientMuzzleFlash",
		Particles = MuzzleParticles,
		Light = MuzzleLight,
		ParticleCount = 20,
		LightDuration = 0.1,
		LightBrightness = 10,
	})

	-- Hook Signals To Tracer
	Salient.Signals.OnFire:Connect(function(Origin, Direction)
		FlashHandler:PlayFlash()
	end)
end

function module._InitializeTracer()
	local CacheContainer = workspace.Client._Internal.ObjectPooling
	local TracerBullet = ReplicatedStorage.Assets.Bullets:WaitForChild('Salient_Bullet')
	local PoolingSize = 70

	local TracerPooling = ObjectCache.new(
		TracerBullet,
		PoolingSize,
		CacheContainer
	)

	local TracerHandler = GunManager.Features.TracerController.new({
		Name = "SalientTracerHandler",
		DefaultSpeed = 2000,
		DefaultWidth = .1,
		DefaultLength = .1,
		FadeTime = .1,
		Container = workspace.Client.Effects.Tracers,
		PoolProvider = function()
			return TracerPooling:GetPart()
		end,
		PoolReturnCallback = function(Part)
			TracerPooling:ReturnPart(Part)
		end,
	})

	-- Hook Signals To Tracer
	Salient.Signals.OnFire:Connect(function(Origin, Direction)
		TracerHandler:SpawnTracer({
			Origin = Origin,
			Direction = Direction,
			MaxDistance = 1000,
		})
	end)
end

function module._InitializeCameraAndLighting()
	local DepthOfField = DOFManager.GetDepthOfField()
	local NearIntensity, FarIntensity = DOFManager.GetBaseIntensity()

	-- Tweens (initialized in functions)
	local CameraZoom = TweenService:Create(Camera,
		TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{FieldOfView = ADS_FOV}
	)

	local CameraNormal = TweenService:Create(Camera,
		TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{FieldOfView = DEFAULT_FOV}
	)
	local LightTween = TweenService:Create(Salient.Data.SpotLight,
		TweenInfo.new(.65),
		{Brightness = 1}
	)

	-- Aim signal for camera and lighting
	Salient.Signals.OnAimChanged:Connect(function(isAiming)
		(isAiming and CameraZoom or CameraNormal):Play()

		if isAiming then
			DepthOfField:SetIntensity(.158, .215)
		else
			DepthOfField:SetIntensity(NearIntensity, FarIntensity)
		end
	end)

	Salient.Signals.OnFire:Connect(function(Origin, Direction)
		DepthOfField:AddIntensity(2)
	end)
end

function module._InitializeMovementHandlers()
	-- Equip handler for walkspeed
	Salient.Signals.OnEquipChanged:Connect(function(IsEquip)
		if IsEquip then
			GlobalMovementHandler:SetDefaultWalkspeed(12)
			GlobalMovementHandler:SetAimingWalkspeed(5)
		else
			GlobalMovementHandler:ResetDefaultWalkspeed()
		end	
	end)

	-- Sprint movement handlers
	local SprintMovement = GlobalMovementHandler:GetSprintMovement()

	SprintMovement.Signals.OnMovementActivated:Connect(function()
		IsSprinting = true
		Salient:SetAiming(false)

		-- Temporarily disable canting animation during sprint
		if IsCanting then
			local GunCanting = Salient.ProceduralAnimator:GetAnimation("GunCanting")
			if GunCanting then
				GunCanting:SetActive(false)
			end
		end

		Salient.ProceduralAnimator.WeaponTilt:SetActive(true)

		local preset = ProceduralConfig.WalkBob.Sprint
		Salient.ProceduralAnimator.WalkBob:SetConfig(preset)
	end)

	SprintMovement.Signals.OnMovementDeactivated:Connect(function()
		IsSprinting = false
		Salient.ProceduralAnimator.WeaponTilt:SetActive(false)

		-- Restore canting if it was active before sprinting
		if IsCanting then
			local GunCanting = Salient.ProceduralAnimator:GetAnimation("GunCanting")
			if GunCanting then
				GunCanting:SetActive(true)
			end
		end

		if Salient:IsAiming() then
			GlobalMovementHandler:StopAiming()
			GlobalMovementHandler:StartAiming()
			Salient.ProceduralAnimator.WalkBob:SetConfig(ProceduralConfig.WalkBob.Aiming)
			return
		end

		local preset = ProceduralConfig.WalkBob.Default
		Salient.ProceduralAnimator.WalkBob:SetConfig(preset)
	end)

	-- Prevent firing while sprinting
	Salient.Signals.OnCanFireCheck:Connect(function(RejectHandler)
		if not Salient:IsAiming() and GlobalMovementHandler:IsSprinting() then
			RejectHandler("Player is sprinting")
			return true
		end
	end)
end

function module._InitializeGunCanting()
	-- Clone the general WeaponTilt
	local GunCanting = Salient.ProceduralAnimator.WeaponTilt:Clone()
	-- Initialize Configs
	GunCanting:SetConfig({
		-- Base state (no cant - normal hold)
		BaseTiltX = 0,
		BaseTiltY = 0,
		BaseTiltZ = 0,
		BaseOffsetX = 0,
		BaseOffsetY = 0,
		BaseOffsetZ = 0,

		WeaponTiltX = 0,     
		WeaponTiltY = -5,    
		WeaponTiltZ = 35,    

		-- Position adjustments for canted hold
		WeaponOffsetX = -0.5,   
		WeaponOffsetY = -0.4,  
		WeaponOffsetZ = 0.05,  

		SmoothSpeed = 6.0    
	})

	-- Register
	Salient.ProceduralAnimator:RegisterAnimation("GunCanting", GunCanting)

	CantingMovement.Signals.OnMovementActivated:Connect(function()
		IsCanting = true

		GunCanting:SetActive(true)
		
		-- Disable ProceduralSway and WeaponTilt when canting
		Salient.ProceduralAnimator.ProceduralSway:SetActive(false)
		Salient.ProceduralAnimator.WeaponTilt:SetActive(false)
	end)

	CantingMovement.Signals.OnMovementDeactivated:Connect(function()
		IsCanting = false
		GunCanting:SetActive(false)

		-- Restore normal WeaponTilt if sprinting
		if IsSprinting then
			Salient.ProceduralAnimator.WeaponTilt:SetActive(true)
		end
		
		if IsAiming then
			Salient.ProceduralAnimator.ProceduralSway:SetActive(true)
		end
	end)
end

function module._InitializeAimHandler()
	Salient.Signals.OnAimChanged:Connect(function(Aiming)
		IsAiming = Aiming

		local recoilPreset = Aiming and ProceduralConfig.Recoil.Aiming or ProceduralConfig.Recoil.Default
		local bobPreset = Aiming and ProceduralConfig.WalkBob.Aiming or ProceduralConfig.WalkBob.Default

		if Aiming then
			Salient.ProceduralAnimator.WeaponTilt:SetActive(false)

			-- Only activate sway if NOT canting
			if not IsCanting then
				Salient.ProceduralAnimator.ProceduralSway:SetActive(true)
			end

			GlobalMovementHandler:StartAiming()
		else
			-- Restore WeaponTilt if sprinting AND not canting
			if IsSprinting and not IsCanting then
				Salient.ProceduralAnimator.WeaponTilt:SetActive(true)
			end

			Salient.ProceduralAnimator.ProceduralSway:SetActive(false)
			GlobalMovementHandler:StopAiming()
		end

		Salient.ProceduralAnimator.CameraRecoil:SetConfig(recoilPreset.Camera)
		Salient.ProceduralAnimator.WeaponRecoil:SetConfig(recoilPreset.Weapon)
		Salient.ProceduralAnimator.WalkBob:SetConfig(bobPreset)
	end)
end

function module._InitializeSignals()
	-- Equip signal for fire mode
	Salient.Signals.OnEquipChanged:Connect(function(NewState)
		GunInputManager.SetFireMode(Salient.Data.FireMode)
	end)

	-- Aim signal for camera and lighting
	Salient.Signals.OnAimChanged:Connect(function(isAiming)
		if isAiming then
			Sounds.AimIn:Play()
		else
			Sounds.AimOut:Play()
		end
	end)

	-- Fire signal
	Salient.Signals.OnFire:Connect(function(Origin, Direction)
		if Salient.Data.Sounds and Salient.Data.Sounds.Fire and #Salient.Data.Sounds.Fire > 0 then
			Salient.Data.Sounds.Fire[math.random(#Salient.Data.Sounds.Fire)]:Play()
		end
	end)
end

-- ========================================
-- MAIN INITIALIZATION
-- ========================================

function module._Initialize()
	module._InitializeGunCanting()
	module._InitializeProceduralAnimations()
	module._InitializeMuzzleFlash()
	module._InitializeTracer()
	module._InitializeCameraAndLighting()
	module._InitializeMovementHandlers()
	module._InitializeAimHandler()
	module._InitializeSignals()
end

-- Initialize everything
module._Initialize()

export type Salient = typeof(Salient)
return Salient :: Salient