function love.run()
    local client = require("websocket").new()
    client:connect("127.0.0.1", 5000)
    client:settimeout(0)
    client:send("hello from love2d")
    print(client:read())
end
