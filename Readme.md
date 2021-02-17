# websocket client pure lua implement for love2d

Event-driven websocket client for love2d in pure lua.

Not all websocket features are implemented, but it works fine.

```lua
local client = require("websocket").new("127.0.0.1", 5000)
client.onmessage = function(message)
    print(message)
end
client.onopen = function()
    client:send("hello from love2d")
    client:close()
end
client.onclose = function()
    print("closed")
end

function love.update()
    client:update()
end
```
