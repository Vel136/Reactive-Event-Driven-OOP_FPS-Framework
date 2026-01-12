--!strict
local timeThrottle: { [any]: number } = {}

return function<T, A...>(
	identifier: T,
	delay: number,
	func: (T, A...) -> (),
	...: A...
): boolean
	local now = os.clock()
	local last = timeThrottle[identifier]
	if last and now - last < delay then
		return false
	end
	
	timeThrottle[identifier] = now
	task.spawn(func, identifier, ...)
	
	task.delay(delay, function()
		-- to avoid memory leaks
		if timeThrottle[identifier] == now then
			timeThrottle[identifier] = nil
		end
	end)
	
	return true
end