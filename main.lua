local client = require("websocket").new("127.0.0.1", 5000)
function client:onmessage(s)
    print(s)
end
function client:onopen()
    self:send("hello from love2d")
    self:close()
end
function client:onerror(e)
    print(e)
end
function client:onclose(code, reason)
    print("closecode: "..code..", reason: "..reason)
end

function love.update()
    client:update()
end
