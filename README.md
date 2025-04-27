# EventEmitter
A simple and lightweight event emitter implementation in Luau.

# API
```LUA
-- Create a new emitter
local Emitter = EventEmitter.new()

-- Listening to an event
local Off = Emitter:On("SomeEvent", function(...)
    print(...) -- Output: Arg1, Arg2
end)

-- Listening once (runs only one time)
Emitter:Once("SomeEvent", function(...)
    print("This runs once!")
end)

-- Wildcard listener (listens to *any* event)
Emitter:On("*", function(...)
    print("Wildcard triggered")
end)

-- Waiting (yields until an event fires)
task.spawn(function()
    local arg1, arg2 = Emitter:Wait("SomeEvent")
    print(arg1, arg2)
end)

-- Emitting an event
Emitter:Emit("SomeEvent", "Arg1", "Arg2")

-- Removing a specific listener
Off()

-- Removing all listeners
Emitter:RemoveAll()
```