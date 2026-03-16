-- BoltActionController.lua
--[[
	Manages bolt-action weapon mechanics including:
	- Bolt cycling system with Promises
	- Shell ejection tracking
	- Round chambering
	- Ammo integration callbacks
]]

local Identity = "BoltActionController"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local Signal     = require(Utilities.Signal)
local Promise    = require(Utilities.Promise)
local LogService = require(Utilities:FindFirstChild("Logger"))
local InputSystem = require(Utilities.IAS)

-- ─── Module ──────────────────────────────────────────────────────────────────

local BoltActionController   = {}
BoltActionController.__index = BoltActionController
BoltActionController.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

-- ─── Getters ─────────────────────────────────────────────────────────────────

--- Returns true if the bolt is ready to fire.
function BoltActionController.IsBoltReady(self: BoltActionController): boolean
	return self._BoltReady
end

--- Returns true if the bolt is currently cycling.
function BoltActionController.IsCycling(self: BoltActionController): boolean
	return self._IsCycling
end

--- Returns true if a round is chambered.
function BoltActionController.HasChamberedRound(self: BoltActionController): boolean
	return self._ChamberedRound
end

--- Returns true if the chambered casing is spent.
function BoltActionController.HasSpentCasing(self: BoltActionController): boolean
	return self._SpentCasing
end

--- Returns the current bolt state snapshot.
function BoltActionController.GetState(self: BoltActionController): BoltActionControllerState
	return {
		Ready          = self._BoltReady,
		IsCycling      = self._IsCycling,
		ChamberedRound = self._ChamberedRound,
		SpentCasing    = self._SpentCasing,
	}
end

--- Returns the metadata table.
function BoltActionController.GetMetadata(self: BoltActionController): any
	return self._Metadata
end

-- ─── Setters ─────────────────────────────────────────────────────────────────

--- Sets the bolt ready state. Fires OnBoltReady if changed.
function BoltActionController.SetBoltReady(self: BoltActionController, ready: boolean)
	local old = self._BoltReady
	self._BoltReady = ready
	if old ~= ready then
		self.Signals.OnBoltReady:Fire(ready)
		Logger:Debug(string.format("SetBoltReady: %s -> %s", tostring(old), tostring(ready)))
	end
end

--- Sets the cycling state.
function BoltActionController.SetCycling(self: BoltActionController, cycling: boolean)
	local old = self._IsCycling
	self._IsCycling = cycling
	if old ~= cycling then
		Logger:Debug(string.format("SetCycling: %s -> %s", tostring(old), tostring(cycling)))
	end
end

--- Sets the chambered round state.
function BoltActionController.SetChamberedRound(self: BoltActionController, chambered: boolean)
	local old = self._ChamberedRound
	self._ChamberedRound = chambered
	if old ~= chambered then
		Logger:Debug(string.format("SetChamberedRound: %s -> %s", tostring(old), tostring(chambered)))
	end
end

--- Sets the spent casing state.
function BoltActionController.SetSpentCasing(self: BoltActionController, spent: boolean)
	local old = self._SpentCasing
	self._SpentCasing = spent
	if old ~= spent then
		Logger:Debug(string.format("SetSpentCasing: %s -> %s", tostring(old), tostring(spent)))
	end
end

--- Sets the bolt ready, chambered, and spent states together.
function BoltActionController.SetBoltState(self: BoltActionController, ready: boolean, chambered: boolean?, spent: boolean?)
	self:SetBoltReady(ready)
	self:SetChamberedRound(if chambered ~= nil then chambered else ready)
	self:SetSpentCasing(if spent ~= nil then spent else false)
end

--- Sets the metadata table.
function BoltActionController.SetMetadata(self: BoltActionController, metadata: any)
	self._Metadata = metadata
end

--- Registers ammo integration callbacks.
function BoltActionController.SetAmmoCallbacks(
	self           : BoltActionController,
	checkAvailable : () -> boolean,
	consumeRound   : (amount: number) -> ()
)
	self.CheckAmmoAvailable = checkAvailable
	self.ConsumeRound       = consumeRound
	Logger:Debug("SetAmmoCallbacks: callbacks registered")
end

-- ─── Notify API ──────────────────────────────────────────────────────────────

--- Marks the chambered round as spent after firing.
function BoltActionController.NotifyFired(self: BoltActionController)
	self:SetBoltReady(false)
	self:SetSpentCasing(true)
	Logger:Debug("NotifyFired: round marked as spent")
end

--- Enables or disables input and resets state on unequip.
function BoltActionController.NotifyEquipped(self: BoltActionController, isEquipped: boolean)
	if self._BoltInput then
		self._BoltInput:SetEnabled(isEquipped)
	end
	if not isEquipped then
		self:_ResetState()
	end
	Logger:Debug(string.format("NotifyEquipped: %s", tostring(isEquipped)))
end

--- Handles post-reload state. Auto-cycles if configured.
function BoltActionController.NotifyReloadComplete(self: BoltActionController)
	if self.Data.AutoBoltOnReload then
		self:SetBoltReady(true)
		self:SetChamberedRound(true)
		self:SetSpentCasing(false)
		self.Signals.OnRoundChambered:Fire()
		Logger:Print("NotifyReloadComplete: bolt auto-cycled")
	end
end

-- ─── Bolt mechanics ──────────────────────────────────────────────────────────

--- Returns true if the weapon is in a fireable state.
function BoltActionController.CanFire(self: BoltActionController): boolean
	return self._BoltReady and self._ChamberedRound and not self._SpentCasing
end

--- Starts a bolt cycle. Returns false if already cycling.
function BoltActionController.CycleBolt(self: BoltActionController): boolean
	if self._IsCycling then
		Logger:Warn("CycleBolt: already cycling")
		return false
	end

	local hasShell      = self._ChamberedRound
	local isSpent       = self._SpentCasing
	local isLiveEject   = self._ChamberedRound and not self._SpentCasing and self._BoltReady

	Logger:Print(string.format("CycleBolt: starting (shell=%s spent=%s live=%s)",
		tostring(hasShell), tostring(isSpent), tostring(isLiveEject)))

	self:SetCycling(true)
	self.Signals.OnBoltCycleStart:Fire()

	if hasShell then
		self.Signals.OnShellEject:Fire({ IsSpent = isSpent, IsLive = isLiveEject } :: ShellEjectInfo)
	end

	if self._BoltPromise then
		self._BoltPromise:cancel()
		self:SetCycling(false)
	end

	self._BoltPromise = Promise.new(function(resolve, _, onCancel)
		local cancelled = false
		onCancel(function()
			cancelled          = true
			self._BoltPromise  = nil
			self:SetCycling(false)
			Logger:Print("CycleBolt: cancelled")
		end)

		task.delay(self.Data.BoltCycleTime, function()
			if cancelled then return end

			local hasAmmo = self.CheckAmmoAvailable and self.CheckAmmoAvailable() or false

			if hasAmmo then
				if isLiveEject and self.ConsumeRound then
					self.ConsumeRound(1)
					Logger:Debug("CycleBolt: wasted live round on eject")
				end

				self:SetBoltReady(true)
				self:SetChamberedRound(true)
				self:SetSpentCasing(false)
				self.Signals.OnRoundChambered:Fire()
				Logger:Print("CycleBolt: round chambered")
			else
				self:SetBoltReady(false)
				self:SetChamberedRound(false)
				self:SetSpentCasing(false)
				Logger:Print("CycleBolt: no ammo, chamber empty")
			end

			self._BoltPromise = nil
			self:SetCycling(false)
			self.Signals.OnBoltCycleComplete:Fire()

			resolve({ Ready = self._BoltReady, Chambered = self._ChamberedRound })
		end)
	end)

	return true
end

--- Cancels an in-progress bolt cycle.
function BoltActionController.CancelBolt(self: BoltActionController)
	if self._BoltPromise then
		self._BoltPromise:cancel()
		self._BoltPromise = nil
	end
end

-- ─── Internal ────────────────────────────────────────────────────────────────

function BoltActionController._InitializeInput(self: BoltActionController)
	local inputName = string.format("%s_BoltActionController", self.Data.Name)
	self._BoltInput = InputSystem.new(inputName)
	self._BoltInput:SetBind(self.Data.KeyBind)

	self._BoltInput.Activated:Connect(function(active: boolean, wasPressed: boolean)
		if not active and not wasPressed then return end
		self:CycleBolt()
	end)

	Logger:Debug(string.format("_InitializeInput: bound for '%s'", self.Data.Name))
end

function BoltActionController._ResetState(self: BoltActionController)
	self:SetBoltReady(false)
	self:SetCycling(false)
	self:SetChamberedRound(false)
	self:SetSpentCasing(false)

	if self._BoltPromise then
		self._BoltPromise:cancel()
		self._BoltPromise = nil
	end

	Logger:Debug("_ResetState: complete")
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Destroys the BoltActionController and cleans up all resources.
function BoltActionController.Destroy(self: BoltActionController)
	Logger:Print("Destroy: cleaning up")

	self:CancelBolt()

	if self._BoltInput then
		self._BoltInput:Destroy()
	end

	for _, signal in self.Signals do
		signal:Destroy()
	end

	self.Data               = nil
	self.CheckAmmoAvailable = nil
	self.ConsumeRound       = nil
	self._Metadata          = nil
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}

--- Creates a new BoltActionController.
function module.new(data: BoltActionControllerData, metadata: any?): BoltActionController
	assert(data,       "BoltActionController.new: data is required")
	assert(data.Name,  "BoltActionController.new: data.Name is required")

	local self: BoltActionController = setmetatable({}, { __index = BoltActionController })

	self.Data                  = data
	self.Data.KeyBind          = data.KeyBind          or Enum.KeyCode.F
	self.Data.BoltCycleTime    = data.BoltCycleTime    or 1.3
	self.Data.AutoBoltOnReload = data.AutoBoltOnReload or false

	self._Metadata = metadata or {}

	self.Signals = {
		OnBoltCycleStart    = Signal.new(),
		OnBoltCycleComplete = Signal.new(),
		OnShellEject        = Signal.new(),
		OnRoundChambered    = Signal.new(),
		OnBoltReady         = Signal.new(),
	}

	self._BoltReady     = false
	self._IsCycling     = false
	self._ChamberedRound = false
	self._SpentCasing   = false

	self.CheckAmmoAvailable = nil
	self.ConsumeRound       = nil
	self._BoltPromise       = nil
	self._BoltInput         = nil

	self:_InitializeInput()

	Logger:Debug(string.format("new: '%s' CycleTime=%.2fs AutoBolt=%s",
		data.Name, self.Data.BoltCycleTime, tostring(self.Data.AutoBoltOnReload)))

	return self
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type BoltActionControllerData = {
	Name             : string,
	KeyBind          : Enum.KeyCode?,
	BoltCycleTime    : number?,
	AutoBoltOnReload : boolean?,
}

export type ShellEjectInfo = {
	IsSpent : boolean,
	IsLive  : boolean,
}

export type BoltActionControllerState = {
	Ready          : boolean,
	IsCycling      : boolean,
	ChamberedRound : boolean,
	SpentCasing    : boolean,
}

export type BoltActionController = typeof(setmetatable({}, { __index = BoltActionController })) & {
	Data                : BoltActionControllerData,
	_BoltReady          : boolean,
	_IsCycling          : boolean,
	_ChamberedRound     : boolean,
	_SpentCasing        : boolean,
	_Metadata           : any,
	_BoltInput          : any,
	_BoltPromise        : any,
	CheckAmmoAvailable  : (() -> boolean)?,
	ConsumeRound        : ((amount: number) -> ())?,
	Signals: {
		OnBoltCycleStart    : Signal.Signal<() -> ()>,
		OnBoltCycleComplete : Signal.Signal<() -> ()>,
		OnShellEject        : Signal.Signal<(info: ShellEjectInfo) -> ()>,
		OnRoundChambered    : Signal.Signal<() -> ()>,
		OnBoltReady         : Signal.Signal<(ready: boolean) -> ()>,
	},
}

return table.freeze(module)