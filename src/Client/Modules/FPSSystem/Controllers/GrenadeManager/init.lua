--!native
--!optimize 2

-- GrenadeManager.lua
--[[
	Client-side grenade orchestrator.
	- Bridges GunInputManager signals to the active grenade
	- Manages grenade equip/unequip lifecycle
	- Handles cook, throw, and cancel input
	- Sits alongside WeaponManager, neither knows about the other
]]

local Identity = "GrenadeManager"

-- ─── Services ────────────────────────────────────────────────────────────────

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities       = ReplicatedStorage.Shared.Modules.Utilities
local GrenadeFolder   = ReplicatedStorage.Client.Modules.FPSSystem.GrenadeSystem

local Camera = workspace.CurrentCamera
local Player = Players.LocalPlayer

-- ─── Modules ─────────────────────────────────────────────────────────────────

local GunInputManager          = require(ReplicatedStorage.Client.Modules.FPSSystem.Controllers.GrenadeInputManager)
local GrenadeRegistry       = require(GrenadeFolder.GrenadeManager)
local GrenadeConfiguration  = require(ReplicatedStorage.Client.Modules.FPSSystem.Configuration.Grenades)

local Janitor    = require(Utilities.Janitor)
local Promise    = require(Utilities.Promise)
local LogService = require(Utilities.Logger)

-- ─── Module ──────────────────────────────────────────────────────────────────

local GrenadeManager   = {}
GrenadeManager.__index = GrenadeManager
GrenadeManager.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

local MainJanitor   = Janitor.new()
local GrenadeJanitor = Janitor.new()

local Data = {
	CurrentGrenade   = nil :: string?,
	CurrentViewmodel = nil :: Model?,
	CurrentPosition  = nil :: Vector3?,
	CurrentDirection = nil :: Vector3?,
}

local CachedCharacter : Model?    = nil
local CachedHumanoid  : Humanoid? = nil

-- ─── Internal: character tracking ────────────────────────────────────────────

local function UpdateCharacterCache()
	CachedCharacter = Player.Character
	if not CachedCharacter then return end
	CachedHumanoid = CachedCharacter:FindFirstChildOfClass("Humanoid") :: Humanoid?
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

	local grenade = GrenadeConfiguration[Data.CurrentGrenade]
	if not grenade then return end


	Data.CurrentViewmodel.PrimaryPart.CFrame = Camera.CFrame

	-- Update throw origin from ThrowAttachment
	local throwAttachment = grenade.Data.ThrowAttachment
	if throwAttachment then
		if throwAttachment:IsA("Attachment") then
			Data.CurrentPosition  = throwAttachment.WorldPosition
		elseif typeof(throwAttachment) == "Instance" then
			Data.CurrentPosition  = throwAttachment.Position
		end
	else
		Data.CurrentPosition  = Camera.CFrame.Position
	end
	
	Data.CurrentDirection = Camera.CFrame.LookVector
end

-- ─── Grenade lifecycle ───────────────────────────────────────────────────────

--- Unequips the current grenade and clears all state.
function GrenadeManager.CleanUp(self: GrenadeManager)
	GrenadeJanitor:Cleanup()

	if Data.CurrentGrenade then
		local existingModel = Camera:FindFirstChild(Data.CurrentGrenade)
		if existingModel then
			existingModel.Parent = ReplicatedStorage.Assets.Viewmodels
		end

		local existingGrenade = GrenadeConfiguration[Data.CurrentGrenade]
		if existingGrenade then
			pcall(function()
				existingGrenade:Unequip()
			end)
		end
	end

	Data.CurrentGrenade   = nil
	Data.CurrentViewmodel = nil
	Data.CurrentPosition  = nil
	Data.CurrentDirection = nil
end

--- Equips the named grenade. Returns a Promise that resolves when complete.
function GrenadeManager.EquipGrenade(self: GrenadeManager, grenadeName: string): any
	return Promise.new(function(resolve, reject)
		local grenade = GrenadeConfiguration[grenadeName]

		if not grenade or not grenade.Data.Model then
			reject("EquipGrenade: invalid grenade '" .. tostring(grenadeName) .. "'")
			return
		end

		grenade:Equip()

		local model = grenade.Data.Model
		model.Parent           = Camera
		Data.CurrentGrenade    = grenadeName
		Data.CurrentViewmodel  = model

		-- Wire grenade-specific signals into the janitor
		GrenadeJanitor:Add(grenade.Signals.OnThrow:Connect(function(origin, velocity)
			Logger:Print(string.format("OnThrow: '%s' thrown", grenadeName))
		end), "Disconnect")

		GrenadeJanitor:Add(grenade.Signals.OnDetonate:Connect(function(position)
			Logger:Print(string.format("OnDetonate: '%s' detonated at %s", grenadeName, tostring(position)))
		end), "Disconnect")

		GrenadeJanitor:Add(grenade.Signals.OnStockEmpty:Connect(function()
			Logger:Print(string.format("OnStockEmpty: '%s' out of stock, unequipping", grenadeName))
			self:CleanUp()
		end), "Disconnect")

		Logger:Print(string.format("EquipGrenade: equipped '%s'", grenadeName))
		resolve()
	end):catch()
end

--- Unequips the current grenade and equips a new one. Pass nil to just unequip.
function GrenadeManager.SwitchGrenade(self: GrenadeManager, grenadeName: string?): any
	if not grenadeName then
		self:CleanUp()
		return Promise.resolve()
	end

	if Data.CurrentGrenade == grenadeName then
		return Promise.reject("SwitchGrenade: already equipped")
	end

	self:CleanUp()
	return self:EquipGrenade(grenadeName)
end

-- ─── Initialization ──────────────────────────────────────────────────────────

--- Wires all input signals and starts the render loop.
function GrenadeManager._Initialize(self: GrenadeManager)

	-- Cook (hold input down)
	MainJanitor:Add(GunInputManager.Signals.GrenadeHeld:Connect(function()
		if not Data.CurrentGrenade then return end

		local grenade = GrenadeConfiguration[Data.CurrentGrenade]
		if not grenade or not grenade:IsEquipped() then return end

		grenade:StartCook()
	end), "Disconnect")

	-- Throw (release input)
	MainJanitor:Add(GunInputManager.Signals.GrenadeReleased:Connect(function()
		if not Data.CurrentGrenade or not Data.CurrentPosition then return end

		local grenade = GrenadeConfiguration[Data.CurrentGrenade]
		if not grenade or not grenade:IsEquipped() then return end

		grenade:Throw(Data.CurrentPosition, Data.CurrentDirection)
	end), "Disconnect")

	-- Cancel cook (e.g. pressing G again or pressing Escape)
	MainJanitor:Add(GunInputManager.Signals.GrenadeCancelled:Connect(function()
		if not Data.CurrentGrenade then return end

		local grenade = GrenadeConfiguration[Data.CurrentGrenade]
		if grenade then
			grenade:CancelCook()
		end
	end), "Disconnect")

	-- Viewmodel update loop
	MainJanitor:Add(RunService.RenderStepped:Connect(function(deltaTime: number)
		UpdateViewmodel(deltaTime)
	end), "Disconnect")

	Logger:Print("_Initialize: GrenadeManager ready")
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--- Returns the currently equipped grenade instance, or nil.
function GrenadeManager.GetCurrentGrenade(self: GrenadeManager): any?
	if not Data.CurrentGrenade then return nil end
	return GrenadeConfiguration[Data.CurrentGrenade]
end

--- Returns the current grenade name, or nil.
function GrenadeManager.GetCurrentGrenadeName(self: GrenadeManager): string?
	return Data.CurrentGrenade
end

--- Returns whether a grenade is currently equipped.
function GrenadeManager.HasGrenadeEquipped(self: GrenadeManager): boolean
	return Data.CurrentGrenade ~= nil
end

-- ─── Singleton ───────────────────────────────────────────────────────────────

local _instance: GrenadeManager

local function GetInstance(): GrenadeManager
	if not _instance then
		_instance = setmetatable({}, GrenadeManager) :: GrenadeManager
		_instance:_Initialize()
	end
	return _instance
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type GrenadeManager = typeof(setmetatable({}, GrenadeManager))

return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("GrenadeManager is read-only")
	end,
}) :: GrenadeManager