--[=[
	@class NetworkService
	Singleton wrapper around Blink for weapon framework networking.
	Provides abstraction and type-safe event handling.
]=]
local module = {}
local RunService = game:GetService('RunService')

module = RunService:IsClient() and require(script.ClientWrapper) or require(script.ServerWrapper)

export type NetworkService = typeof(module)

return module :: NetworkService