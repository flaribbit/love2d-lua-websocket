# websocket client pure lua implement for love2d

Event-driven websocket client for love2d in pure lua, which aims to be simple and easy to use.

Not all websocket features are implemented, but it works fine. Tested with aiohttp(python) and ws(nodejs) library.

⚠️ `wss://` connection (websocket with TLS) is not supported. If you need that, you may try [löve-ws](https://github.com/holywyvern/love-ws).

## Quick start
Just copy `websocket.lua` to your project directory, and write code as the following example.

```lua
local client = require("websocket").new("127.0.0.1", 5000)
function client:onmessage(message)
    print(message)
end
function client:onopen()
    self:send("hello from love2d")
    self:close()
end
function client:onclose(code, reason)
    print("closecode: "..code..", reason: "..reason)
end

function love.update()
    client:update()
end
```

## API
* `websocket.new(host: string, port: int, path?: string) -> client`
* `function client:onopen()`
* `function client:onmessage(message: string)`
* `function client:onerror(error: string)`
* `function client:onclose(code: int, reason: string)`
* `client.status -> int`
* `client:send(message: string)`
* `client:close(code?: int, reason?: string)`
* `client:update()`
