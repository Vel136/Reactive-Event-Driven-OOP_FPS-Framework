-- M67.lua

-- Services
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- References
local GrenadeSystem = ReplicatedStorage.Client.Modules.FPSSystem.GrenadeSystem

local CameraShaker = require(ReplicatedStorage.Shared.Modules.Utilities.CameraShaker)
-- Required Modules
local GrenadeManager  = require(GrenadeSystem.GrenadeManager)
local BlastController = require(GrenadeSystem.GrenadeManager.GrenadeInstance.BlastController)
local GunInputManager    = require(ReplicatedStorage.Client.Modules.FPSSystem.Controllers.GunInputManager)
local M67Data         = require(ReplicatedStorage.Shared.Modules.FPSSystem.Configuration.Grenades.M67)

local GrenadeAnimator	= require(ReplicatedStorage.Client.Modules.FPSSystem.AnimationSystem.GrenadeAnimator)
local GlobalMovementHandler = require(ReplicatedStorage.Client.Modules.MovementSystem.GlobalMovementHandler)

-- Constants
local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local Sounds = ReplicatedStorage.Assets.Sounds.M67

local Shaker = CameraShaker.new(Enum.RenderPriority.Camera.Value, function(shakeCFrame)
	Camera.CFrame = Camera.CFrame * shakeCFrame
end)
Shaker:Start()
-- ─── Module ──────────────────────────────────────────────────────────────────

local module = {}

-- ─── Grenade Initialization ──────────────────────────────────────────────────

local M67 = GrenadeManager.new(
	M67Data.ID,
	M67Data,
	BlastController.new(M67Data.Blast)
)
M67.Animator = GrenadeAnimator.new(M67, M67Data.Model)

M67.Ballistics.Behavior.CanBounceFunction = function()
	return true
end
-- ─── State tracking ──────────────────────────────────────────────────────────

local IsCooking  = false
local IsEquipped = false

-- ─── Initialization ──────────────────────────────────────────────────────────


function module._InitializeProjectile()
	-- Provide the grenade model as the cosmetic bullet so BounceSolver moves it
	M67.Ballistics.Behavior.CosmeticBulletProvider = function()
		local projectileTemplate = workspace.Effects.Grenades:WaitForChild("Handle")
		local projectile = projectileTemplate:Clone()
		projectile.Parent = workspace.Effects.Grenades
		return projectile
	end

	M67.Ballistics.Behavior.CosmeticBulletContainer = workspace.Effects.Grenades
end
function module._InitializeCameraEffects()
	-- Shake camera on detonation
	M67.Signals.OnDetonate:Connect(function(position: Vector3)
		local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local distance = (hrp.Position - position).Magnitude
		local radius   = M67Data.Blast.Radius
		
		if distance > radius * 1.5 then return end

		-- Scale shake intensity by distance
		local intensity = 1 - math.clamp(distance / radius, 0, 1)
		Shaker:ShakeOnce(
			intensity * 5,   -- magnitude  — scale to taste
			3,               -- roughness
			0.1,             -- fade in
			0.8              -- fade out
		)
		
	end)
end

function module._InitializeSignals()
	-- Equip signal
	M67.Signals.OnEquipChanged:Connect(function(isEquipped: boolean)
		IsEquipped = isEquipped
	end)

	-- Cook started — play pin pull sound
	M67.Signals.OnCookStarted:Connect(function()
		IsCooking = true
		Sounds.PinPull:Play()
	end)

	-- Cook cancelled — no throw, reset
	M67.Signals.OnCookCancelled:Connect(function()
		IsCooking = false
	end)

	-- Throw — play throw sound, store active part reference
	M67.Signals.OnThrow:Connect(function(origin: Vector3, velocity: Vector3)
		IsCooking = false
		Sounds.Throw:Play()
	end)

	-- Detonate — play explosion sound
	M67.Signals.OnDetonate:Connect(function(position: Vector3)
		Sounds.Explode:Play()
	end)

	-- Out of stock
	M67.Signals.OnStockEmpty:Connect(function()
		IsEquipped = false
	end)

	M67.Signals.OnCanThrowCheck:Connect(function(RejectHandler)
		if GlobalMovementHandler:IsSprinting() then
			RejectHandler("Player is sprinting")
		end
	end)
end

function module._InitializeBlastEffects()
	-- Hook into BlastController hits to play per-target effects
	M67.BlastController.Signals.OnTargetHit:Connect(function(hitData)
		-- hitData: { Character, Distance, Damage, HasLoS }
		-- Fire server damage request, play hit markers, etc.
	end)

	M67.BlastController.Signals.OnDetonated:Connect(function(position, hits)
		-- Spawn explosion VFX at position
		local explosion = Instance.new("Explosion")
		explosion.Position    = position
		explosion.BlastRadius = 0   -- Visual only, damage is handled by BlastController
		explosion.BlastPressure = 0
		explosion.Parent      = workspace
	end)
end

-- ========================================
-- MAIN INITIALIZATION
-- ========================================

function module._Initialize()
	module._InitializeProjectile()
	module._InitializeSignals()
	module._InitializeBlastEffects()
	module._InitializeCameraEffects()
end

module._Initialize()

export type M67 = typeof(M67)
return M67 :: M67