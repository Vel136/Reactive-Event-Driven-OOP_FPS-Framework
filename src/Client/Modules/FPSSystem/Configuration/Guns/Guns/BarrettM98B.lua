-- ============================================================================
-- BARRETT M98B WEAPON SETUP (OPTIMIZED)
-- ============================================================================

-- Services
local TweenService = game:GetService('TweenService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService("Players")

-- References
local Client = ReplicatedStorage.Client
local FPSClient = Client.Modules.FPSSystem
local Utilities = ReplicatedStorage.Shared.Modules.Utilities
local Weapon = FPSClient.GunSystem
-- Required Modules

-- Weapons 
local ProceduralGunDecorator = require(Weapon.ProceduralGunDecorator)
local GunManager = require(Weapon.GunManager)

-- Input Handling & Config
local GunInputManager = require(FPSClient.Controllers.GunInputManager)
local GunData = require(ReplicatedStorage.Shared.Modules.FPSSystem.Configuration.Guns.BarrettM98B)

-- Additional Modules
local ObjectCache = require(Utilities.ObjectCache)
local DepthOfFieldModule = require(Utilities.DepthOfField)
local CameraShake = require(Utilities.CameraShaker)


local BoltActionControllerPreset = GunManager.Features.BoltActionController

-- Constants
local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local DEFAULT_FOV = 90
local ADS_FOV = 15 -- Sniper scope zoom
local TWEEN_DURATION = 0.3 -- Slower for heavy sniper
local TRACER_POOL_SIZE = 15

local Sounds = ReplicatedStorage.Assets.Sounds.BarrettM98B

-- ============================================================================
-- PROCEDURAL ANIMATION PRESETS
-- ============================================================================

local RecoilPresets = {
	Default = {
		Camera = {
			SpringDamping = 0.4,
			SpringSpeed = 20,
			Pitch = {15, 30},
			Yaw = {-3, 3},
			Roll = {-4, 4}
		},
		Weapon = {
			KickIntensity = 0.15,
			RecoverySpeed = 10,
			KickSnapSpeed = 30.0,
			Rotation = {
				X = {Min = math.rad(0.5), Max = math.rad(6)},
				Y = {Min = math.rad(-0.1), Max = math.rad(0.2)},
				Z = {Min = math.rad(-0.15), Max = math.rad(0.25)},
			},
			Position = {
				X = {Min = -0.08, Max = 0.08},
				Y = {Min = -0.05, Max = 0.05},
				Z = {Min = 0.15, Max = 0.3},
			},
			MaxRotation = {
				X = math.rad(8),
				Y = math.rad(10),
				Z = math.rad(8),
			},
			MaxPosition = {
				X = 0.6,
				Y = 0.6,
				Z = 1.5,
			},
		}
	},
	Aiming = {
		Camera = {
			SpringDamping = 0.7,
			SpringSpeed = 35,
			Pitch = {6, 12},
			Yaw = {-1.5, 1.5},
			Roll = {-2, 2}
		},
		Weapon = {
			KickIntensity = 0.08,
			RecoverySpeed = 14,
			KickSnapSpeed = 32.0,
			Rotation = {
				X = {Min = math.rad(0.25), Max = math.rad(3)},
				Y = {Min = math.rad(-0.05), Max = math.rad(0.1)},
				Z = {Min = math.rad(-0.08), Max = math.rad(0.12)},
			},
			Position = {
				X = {Min = -0.03, Max = 0.03},
				Y = {Min = -0.02, Max = 0.02},
				Z = {Min = 0.08, Max = 0.15},
			},
			MaxRotation = {
				X = math.rad(4),
				Y = math.rad(5),
				Z = math.rad(4),
			},
			MaxPosition = {
				X = 0.3,
				Y = 0.3,
				Z = 0.75,
			},
		}
	}
}

local WalkBobPresets = {
	Default = {
		MovementIntensity = 0.035,
		HorizontalFrequency = 7,
		VerticalFrequency = 14,
		DepthFrequency = 7,
		RotationIntensity = 3.5,
	},
	Sprint = {
		MovementIntensity = 0.09,
		HorizontalFrequency = 7,
		VerticalFrequency = 14,
		DepthFrequency = 14,
		DepthIntensity = 1.6,
		RotationIntensity = 4,
	},
	Aiming = {
		MovementIntensity = 0.003,
		HorizontalFrequency = 6,
		VerticalFrequency = 12,
		DepthFrequency = 6,
		RotationIntensity = 0.5,
	}
}

-- ============================================================================
-- WEAPON INITIALIZATION
-- ============================================================================

local EjectData = {
	EjectRight = 1.5,
	EjectUp = 0.8,
	EjectForward = -0.4,
	BaseSpeed = 28,
	SpeedVariance = 1.5,
	AngleNoise = math.rad(5),
	AngularVelocity = {
		X = {Min = -8, Max = 8},
		Y = {Min = -15, Max = 15},
		Z = {Min = -8, Max = 8},
	},
	CasingLifetime = 1,
	PoolSize = 10,
	PoolContainer = workspace.Effects.Bullets:WaitForChild('BarrettM98B'),
	UseRenderStepped = true,
}
local BarretInstance = GunManager.new(2, GunData)

print("BARRET GUN INSTANCE ", BarretInstance)
local BarrettM98B = ProceduralGunDecorator.new(BarretInstance, {}, {
	Attachment = GunData.ShellEjectAttachment,
	Bullets = {
		Empty = {
			Bullet = workspace.Effects.Bullets:WaitForChild('BarrettM98B'):WaitForChild('BarrettM98B_Shell'),
			AutoEjectShells = false,
			Data = EjectData
		},
		Live = {
			Bullet = workspace.Effects.Bullets:WaitForChild('BarrettM98B'):WaitForChild('.50 Cal'),
			AutoEjectShells = false,
			Data = EjectData,
		},
	},
})

-- Setup bullet cosmetics
BarrettM98B.Ballistics.Behavior.CosmeticBulletContainer = workspace:WaitForChild('Effects')

local cachedTracers = ObjectCache.new(
	ReplicatedStorage.Assets.Bullets:WaitForChild('BarrettM98B_Bullet'),
	TRACER_POOL_SIZE,
	workspace:WaitForChild('Effects')
)

BarrettM98B.Ballistics.Behavior.CosmeticBulletProvider = function()
	return cachedTracers:GetPart()
end

-- ============================================================================
-- BOLT ACTION SETUP
-- ============================================================================
local BoltActionController = BoltActionControllerPreset.new({
	Name = "BarrettM98B",
	KeyBind = Enum.KeyCode.F,
	BoltCycleTime = 1.3,
	AutoBoltOnReload = false,
})
-- Setup BoltActionController callbacks
BoltActionController.CheckAmmoAvailable = function(...)
	return BarrettM98B.AmmoController:HasAmmo(...)
end

BoltActionController.ConsumeRound = function(...)
	return BarrettM98B.AmmoController:ConsumeAmmo(...)
end

BarrettM98B.BoltActionController = BoltActionController

-- Integrate bolt action with weapon
BarrettM98B.Signals.OnFire:Connect(function()
	BoltActionController:NotifyFired()
end)

BarrettM98B.Signals.OnEquipChanged:Connect(function(isEquipped)
	BoltActionController:NotifyEquipped(isEquipped)
end)

BarrettM98B.Signals.OnReloadComplete:Connect(function()
	BoltActionController:NotifyReloadComplete()
end)

-- Override CanFireCondition to include bolt action check
BarrettM98B.Signals.OnCanFireCheck:Connect(function(RejectHandler)
	local CanFire = BarrettM98B.BoltActionController:CanFire()
	
	RejectHandler("Cant not fire due to bolt action validation")
	return true
end)

-- ============================================================================
-- BOLT ACTION VISUAL/AUDIO HANDLERS
-- ============================================================================

-- Handle bolt cycle start (animation + sound)
BarrettM98B.BoltActionController.Signals.OnBoltCycleStart:Connect(function()
	-- Play bolt animation
	if BarrettM98B.Animator then
		local animationData = BarrettM98B.Data.Animations["BoltActionController"]
		if animationData then
			BarrettM98B.Animator:PlayCustomAnimation("BoltCycling")
		end
	end

	-- Play bolt action sound
	if Sounds.BoltActionController then
		Sounds.BoltActionController:Play()
	end
end)

-- Handle shell ejection
BarrettM98B.BoltActionController.Signals.OnShellEject:Connect(function(ejectInfo)
	task.wait(0.4) -- Eject delay

	-- Play bolt release sound
	if Sounds["Bolt Release"] then
		Sounds["Bolt Release"]:Play()
	end

	-- Eject appropriate shell type
	if BarrettM98B.BulletEject then
		if ejectInfo.IsSpent and BarrettM98B.BulletEject.Empty then
			-- Eject spent casing
			BarrettM98B.BulletEject.Empty:Eject()
			print("Eject Empty")
		elseif ejectInfo.IsLive and BarrettM98B.BulletEject.Live then
			-- Eject unfired round
			BarrettM98B.BulletEject.Live:Eject()
			print("Eject Live")
		end
	end
end)

BarrettM98B.BoltActionController.Signals.OnRoundChambered:Connect(function()

end)


BarrettM98B.BoltActionController.Signals.OnBoltReady:Connect(function(isReady)

end)

-- Register bolt animation if animator exists
if BarrettM98B.Animator then
	local animationData = BarrettM98B.Data.Animations["BoltActionController"]
	if animationData then
		BarrettM98B.Animator:RegisterCustomAnimation(
			"BoltCycling",
			animationData,
			6, -- Animation speed
			false,
			Enum.AnimationPriority.Action
		)
	end
end

-- ============================================================================
-- PROCEDURAL ANIMATIONS SETUP
-- ============================================================================
local ModelScale = 1

BarrettM98B.ProceduralAnimator.WeaponTilt:SetConfig({
	WeaponTiltX = 30,
	WeaponTiltY = 50,
	WeaponTiltZ = 25,
	WeaponOffsetX = -0.6 * ModelScale,
	WeaponOffsetY = -2.6 * ModelScale,
	WeaponOffsetZ = 0.3 * ModelScale,
	SmoothSpeed = 8.0,
	BaseTiltX = 0,
	BaseTiltY = 0,
	BaseTiltZ = 0,
	BaseOffsetX = -0.7 * ModelScale,
	BaseOffsetY = 0.75 * ModelScale,
	BaseOffsetZ = 1 * ModelScale,
})

BarrettM98B.ProceduralAnimator.CameraRecoil:SetConfig(RecoilPresets.Default.Camera)
BarrettM98B.ProceduralAnimator.WeaponRecoil:SetConfig(RecoilPresets.Default.Weapon)
BarrettM98B.ProceduralAnimator.WalkBob:SetConfig(WalkBobPresets.Default)

BarrettM98B.ProceduralAnimator.ProceduralSway:SetConfig({
	AimTime = GunData.AimTime or 0.45,
	SwaySpeed = 0.25,
	BreathRate = 0.25,
})

-- Sprint handler
GunInputManager.Signals.SprintStarted:Connect(function()
	local preset = WalkBobPresets.Sprint
	BarrettM98B.ProceduralAnimator.WalkBob:SetConfig(preset)
end)
GunInputManager.Signals.SprintStopped:Connect(function(Sprinting)
	local preset = WalkBobPresets.Default
	BarrettM98B.ProceduralAnimator.WalkBob:SetConfig(preset)
end)
-- Aim handler
BarrettM98B.Signals.OnAimChanged:Connect(function(isAiming)
	local recoilPreset = isAiming and RecoilPresets.Aiming or RecoilPresets.Default
	local bobPreset = isAiming and WalkBobPresets.Aiming or WalkBobPresets.Default

	BarrettM98B.ProceduralAnimator.CameraRecoil:SetConfig(recoilPreset.Camera)
	BarrettM98B.ProceduralAnimator.WeaponRecoil:SetConfig(recoilPreset.Weapon)
	BarrettM98B.ProceduralAnimator.WalkBob:SetConfig(bobPreset)
end)

-- ============================================================================
-- CAMERA & DOF SETUP
-- ============================================================================

local CameraShaker = CameraShake.new(Enum.RenderPriority.Camera.Value + 1, function(shakeCf)
	Camera.CFrame = Camera.CFrame * shakeCf
end)
CameraShaker:Start()

local CameraZoom = TweenService:Create(Camera,
	TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	{FieldOfView = ADS_FOV}
)

local CameraNormal = TweenService:Create(Camera,
	TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	{FieldOfView = DEFAULT_FOV}
)

-- ============================================================================
-- WEAPON EVENT HANDLERS
-- ============================================================================

BarrettM98B.Signals.OnEquipChanged:Connect(function(NewState)
	GunInputManager.SetFireMode(BarrettM98B.Data.FireMode)
	
end)

BarrettM98B.Signals.OnAimChanged:Connect(function(isAiming)
	(isAiming and CameraZoom or CameraNormal):Play()

	if isAiming then
		Sounds.AimIn:Play()
	else
		Sounds.AimOut:Play()
	end
end)

BarrettM98B.Signals.OnReloadComplete:Connect(function()
	CameraNormal:Play()
end)

-- ============================================================================
-- FIRE HANDLER
-- ============================================================================

local Particles = {}
for _, Child in pairs(BarrettM98B.Data.BarrelAttachment:GetChildren()) do
	if Child:IsA("ParticleEmitter") then
		table.insert(Particles, Child)
	end
end

BarrettM98B.Signals.OnPreFire:Connect(function(Origin, Direction)
	-- Sound
	if BarrettM98B.Data.Sounds and BarrettM98B.Data.Sounds.Fire and #BarrettM98B.Data.Sounds.Fire > 0 then
		BarrettM98B.Data.Sounds.Fire[math.random(#BarrettM98B.Data.Sounds.Fire)]:Play()
	end

	-- Muzzle effects (enhanced for Barrett)
	for _, Particle in pairs(Particles) do
		Particle:Emit(40)
	end

	local Light = BarrettM98B.Data.BarrelAttachment:FindFirstChild("Light")
	if Light then
		Light.Enabled = true
		task.delay(0.15, function() Light.Enabled = false end)
	end


	-- Camera shake (very strong for Barrett)
	CameraShaker:ShakeOnce(0.25, 2.5, 0, 0.6, Vector3.new(0.15, 0.15, 0.15), Vector3.new(2.5, 0.8, 0.3))
end)

-- ============================================================================
-- BULLET COSMETICS
-- ============================================================================

function BarrettM98B:_OnBulletTravel(Context)
	local bullet = Context.Bullet
	if not bullet then return false end

	-- Larger bullet size for .338 Lapua
	bullet.Size = Vector3.new(0.15, 0.15, Context.Length * 1.2)
	bullet.CFrame = CFrame.lookAt(Context.LastPoint, Context.LastPoint + Context.Direction)
		* CFrame.new(0, 0, -Context.Length / 2)
end

function BarrettM98B:_OnBulletTerminating(Context)
	if Context.Bullet then
		cachedTracers:ReturnPart(Context.Bullet)
	end
end

export type BarrettM98B = typeof(BarrettM98B)
return BarrettM98B :: BarrettM98B