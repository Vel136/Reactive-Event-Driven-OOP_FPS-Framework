-- Typewriter Module for Roblox (Luau)
local Typewriter = {}
Typewriter.__index = Typewriter

function Typewriter.new(options)
	local self = setmetatable({}, Typewriter)

	options = options or {}
	self.typeSpeed = options.typeSpeed or 0.05
	self.deleteSpeed = options.deleteSpeed or 0.03
	self.pauseDuration = options.pauseDuration or 1
	self.isRunning = false
	self.currentThread = nil

	return self
end

function Typewriter:type(textObject, text, onComplete)
	text = tostring(text or "") or ""
	if self.isRunning then
		self:stop()
	end

	self.isRunning = true
	textObject.Text = ""

	self.currentThread = task.spawn(function()
		for i = 1, #text do
			if not self.isRunning then break end

			textObject.Text = string.sub(text, 1, i)
			task.wait(self.typeSpeed)
		end

		self.isRunning = false
		if onComplete then
			onComplete()
			print("COMPLETE")
		end
	end)
end

function Typewriter:delete(textObject, onComplete)
	if self.isRunning then
		self:stop()
	end

	self.isRunning = true
	local text = textObject.Text

	self.currentThread = task.spawn(function()
		for i = #text, 0, -1 do
			if not self.isRunning then break end

			textObject.Text = string.sub(text, 1, i)
			task.wait(self.deleteSpeed)
		end

		self.isRunning = false
		if onComplete then
			onComplete()
		end
	end)
end

function Typewriter:typeAndDelete(textObject, text, onComplete)
	text = tostring(text or "") or ""
	self:type(textObject, text, function()
		task.wait(self.pauseDuration)
		self:delete(textObject, onComplete)
	end)
end

function Typewriter:loop(textObject, texts)
	local index = 1

	local function cycle()
		if not self.isRunning then return end

		self:typeAndDelete(textObject, texts[index], function()
			index = index % #texts + 1
			task.wait(0.5)
			cycle()
		end)
	end

	self.isRunning = true
	cycle()
end

function Typewriter:stop()
	self.isRunning = false
	if self.currentThread then
		task.cancel(self.currentThread)
		self.currentThread = nil
	end
end

return Typewriter