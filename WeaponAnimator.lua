local module = {}

local SCRIPT_NAME = "WeaponAnimator"
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local SoundService = game:GetService('SoundService')

local WeaponType = require(ReplicatedStorage.SharedModules.Cores.WeaponInstance.WeaponType)
local Observer = require(ReplicatedStorage.SharedModules.Utilities.Observer)
local Janitor = require(ReplicatedStorage.SharedModules.Utilities.Janitor)
local Logger = require(ReplicatedStorage.SharedModules.Utilities.LogService)

local mainJanitor = Janitor.new()


function module.BindWeaponAnimation(Weapon : WeaponType.Gun)
	if not Weapon then return false end
	local model = workspace.CurrentCamera:FindFirstChild(Weapon.Data.Name)
	if not model then return false end
	local AnimationController = model:FindFirstChildOfClass("AnimationController")
	if not AnimationController then
		AnimationController = Instance.new('AnimationController')
		AnimationController.Parent = model
		
		local Animator = Instance.new("Animator")
		Animator.Parent = AnimationController
	end
	local Animator = AnimationController:FindFirstChildOfClass("Animator")
	
	if not Animator then
		Animator = Instance.new("Animator")
		Animator.Parent = AnimationController
	end
	
	if Weapon.Data.Animations.Fire then
		local ShootAnim: AnimationTrack = Animator:LoadAnimation(Weapon.Data.Animations.Fire)
		ShootAnim.Priority = Enum.AnimationPriority.Action
		ShootAnim.Looped = false

		mainJanitor:Cleanup()
		local shootObserver = Weapon.Signals.OnShoot:Connect(function()
			if ShootAnim.IsPlaying then
				ShootAnim:Stop()
			end
			
			
			ShootAnim:Play()
		end)
		
		mainJanitor:Add(shootObserver,"Disconnect")
	end
	
	if Weapon.Data.Animations.Aim then
		local AimAnim: AnimationTrack = Animator:LoadAnimation(Weapon.Data.Animations.Aim)
		AimAnim.Priority = Enum.AnimationPriority.Action
		AimAnim.Looped = true
		local aimObserver = Weapon.Signals.OnAimChanged:Connect(function(isAiming)
			if isAiming and not AimAnim.IsPlaying then
				AimAnim:Play(.2)
			else
				AimAnim:Stop(.2)
			end
		end)
		
		mainJanitor:Add(aimObserver,"Disconnect")
	end
	if Weapon.Data.Animations.Reload then
		local ReloadAnim: AnimationTrack = Animator:LoadAnimation(Weapon.Data.Animations.Reload)
		ReloadAnim.Priority = Enum.AnimationPriority.Action
		ReloadAnim.Looped = false
		local onReloadObserver = Weapon.Signals.OnReload:Connect(function()
			if ReloadAnim.IsPlaying then return false end
			print("playing reload")
			ReloadAnim:Play()
			
			
			print(ReloadAnim.Length)
		end)
		
		mainJanitor:Add(onReloadObserver,"Disconnect")
	end
	
	if Weapon.Data.Animations.Equip then
		local EquipAnim: AnimationTrack = Animator:LoadAnimation(Weapon.Data.Animations.Equip)
		EquipAnim.Priority = Enum.AnimationPriority.Action
		EquipAnim.Looped = false
		local onReloadObserver = Weapon.Signals.OnEquipChanged:Connect(function(isEquipped)
			if EquipAnim.IsPlaying or not isEquipped then return false end

			EquipAnim:Play()
		end)

		mainJanitor:Add(onReloadObserver,"Disconnect")
	end

end

function module.UnbindWeaponAnimation()
	mainJanitor:Cleanup()
end




return module
