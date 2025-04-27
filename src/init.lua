--!strict

--[[
	@author kaxel03
	@license MIT

	A simple and lightweight event emitter implementation in Luau.
	Github: https://github.com/kaxx1/EventEmitter

	Credits to stravant's GoodSignal for the methods `Once`, `Wait` and `RemoveAll` (DisconnectAll).
	GoodSignal GitHub: https://github.com/stravant/goodsignal

	Functions:

		EventEmitter.new() -> [EventEmitter]

	Public methods:

		EventEmitter:On(event, callback) -> [() -> ()]
			event 	 [string] -- Name of the event to listen to
			callback [Callback] -- Function to call when the event is emitted

		EventEmitter:Off(event, callback) -> [void]
			event 	 [string] -- Name of the event to remove the callback from
			callback [Callback] -- Function to stop listening with

		EventEmitter:Emit(event, ...) -> [void]
			event [string] -- Name of the event to trigger
			...   [any] -- Argument(s) to pass to the event listener(s)

		EventEmitter:Once(event, callback) -> [() -> ()]
			event 	 [string] -- Name of the event to listen to once
			callback [Callback] -- Function to call the next time the event is emitted

		EventEmitter:Wait(event) -> [...any]
			event [string] -- Name of the event to wait for

		EventEmitter:RemoveAll() -> [void]

		EventEmitter:Destroy() -> [void]

	Private members:

		_Listeners		[{[string]: {Callback}}] -- Table storing all event listeners
		_YieldedThreads [{[thread]: boolean?}?] -- Threads currently waiting for events
]]

--<< TYPES >>--
export type EventEmitter = {
	-- Public methods
	On: (self: EventEmitter, event: string, callback: Callback) -> () -> ();
	Off: (self: EventEmitter, event: string, callback: Callback) -> ();
	Emit: (self: EventEmitter, event: string, ...any) -> ();
	Once: (self: EventEmitter, event: string, callback: Callback) -> () -> ();
	Wait: (self: EventEmitter, event: string) -> ...any;
	RemoveAll: (self: EventEmitter) -> ();
	Destroy: (self: EventEmitter) -> ();
}

type EventEmitterInternal = EventEmitter & {
	-- Private variables
	_Listeners: { [string]: { Callback } };
	_YieldedThreads: { [thread]: boolean? }?;
}

type Callback = (...any) -> ()

--<< CONSTANTS >>--
local WILDCARD = "*"

--< HELPER FUNCTIONS >>--
--[[
	Spawns a new thread for each callback in an event.

	@param callbacks {Callback} -- The events' callbacks
	@param ... any -- Argument(s) emitted from an event
]]
local function SpawnCallbacks(callbacks: { Callback }, ...)
	for _, callback in callbacks do
		task.spawn(callback, ...)
	end
end

--<< CLASS >>--
--[[
	EventEmitter provides a simple system for subscribing, emitting, and managing events.

	@class EventEmitter
]]
local EventEmitter = {}
EventEmitter.__index = EventEmitter

--<< CONSTRUCTOR >>--
--[[
	Creates a new event emitter.

	@return EventEmitter -- Event emitter object
	@within EventEmitter
]]
function EventEmitter.new(): EventEmitter
	local self = setmetatable({} :: EventEmitterInternal , EventEmitter)

	self._Listeners = {}
	self._YieldedThreads = nil

	return self :: EventEmitter
end

--<< PUBLIC METHODS >>--
--[[
	Listens to the specified event with a callback that will be triggered upon emitting the event.

	@param event string -- Name of the event to listen to
	@param callback Callback -- Function to call when the event is emitted
	@return () -> () -- Function to disconnect listener
	@within EventEmitter
]]
function EventEmitter.On(
	self: EventEmitterInternal,
	event: string,
	callback: Callback
): () -> ()
	if not self._Listeners[event] then
		self._Listeners[event] = {}
	end

	table.insert(self._Listeners[event], callback)

	return function()
		self:Off(event, callback)
	end
end

--[[
	Removes the specified callback from the specified event.
	Also removes the event if it has no callbacks.

	@param event string -- Name of the event to remove the callback from
	@param callback Callback -- Function to stop listening with
	@within EventEmitter
]]
function EventEmitter.Off(self: EventEmitterInternal, event: string, callback: Callback)
	local Callbacks = self._Listeners[event]

	if not Callbacks then
		return
	end

	-- Loops through the callbacks backwards
	-- Attempts to find the specified callback and remove it
	for i = #Callbacks, 1, -1 do
		if Callbacks[i] == callback then
			table.remove(Callbacks, i)

			break
		end
	end

	-- If the callbacks are empty, remove the event
	if #Callbacks == 0 then
		self._Listeners[event] = nil
	end
end

--[[
	Emits an event to all listeners of that event together with optional parameters.

	@param event string -- Name of the event to trigger
	@param ... any -- Argument(s) to pass to the event listener(s)
	@within EventEmitter
]]
function EventEmitter.Emit(self: EventEmitterInternal, event: string, ...)
	local Callbacks = self._Listeners[event]
	local Wildcard = self._Listeners[WILDCARD]

	-- Check if the event is valid
	-- Prevent wildcard from triggering from non-existing events
	if not Callbacks then
		return
	end

	SpawnCallbacks(Callbacks, ...)

	if Wildcard then
		SpawnCallbacks(Wildcard, ...)
	end
end

--[[
	Connects a function to the specified event, which will be called the next time the event is emitted.
	Once the event is emitted, it'll remove the callback from the event.

	@param event string -- Name of the event to listen to once
	@param callback Callback -- Function to call the next time the event is emitted
	@return () -> () -- Function to disconnect listener
	@within EventEmitter
]]
function EventEmitter.Once(
	self: EventEmitterInternal,
	event: string,
	callback: Callback
): () -> ()
	local Off
	local Done = false

	Off = self:On(event, function(...)
		if Done then
			return
		end

		Done = true

		Off()
		callback(...)
	end)

	return Off
end

--[[
	Yields the current thread until the event is recieved, and returns the argument(s) emitted from the event.

	@param event string -- Name of the event to wait for
	@return ...any -- Argument(s) emitted from the event
	@within EventEmitter
]]
function EventEmitter.Wait(self: EventEmitterInternal, event: string): ...any
	local YieldedThreads = self._YieldedThreads :: { [thread]: boolean? }

	if not YieldedThreads then
		YieldedThreads = {}
		self._YieldedThreads = YieldedThreads
	end

	local Thread = coroutine.running()
	YieldedThreads[Thread] = true

	self:Once(event, function(...)
		YieldedThreads[Thread] = nil
		task.spawn(Thread, ...)
	end)

	return coroutine.yield()
end

--[[
	Removes all listeners and cancels any yielding threads.

	@within EventEmitter
]]
function EventEmitter.RemoveAll(self: EventEmitterInternal)
	for _, callbacks in self._Listeners do
		table.clear(callbacks)
	end

	table.clear(self._Listeners)

	if self._YieldedThreads then
		for thread in self._YieldedThreads do
			if coroutine.status(thread) == "suspended" then
				warn(debug.traceback(thread, `[EventEmitter]: Event removed; yielded thread disconnected`, 2))
				task.cancel(thread)
			end
		end

		table.clear(self._YieldedThreads)
	end
end

--[[
	Alias for `EventEmitter.RemoveAll`

	@see EventEmitter.RemoveAll
	@within EventEmitter
]]
EventEmitter.Destroy = EventEmitter.RemoveAll

return {
	new = EventEmitter.new
}