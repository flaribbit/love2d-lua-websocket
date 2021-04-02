--[[
websocket client pure lua implement for love2d
by flaribbit

usage:
    local client = require("websocket").new("127.0.0.1", 5000)
    client.onmessage = function(s) print(s) end
    client.onopen = function() client:send("hello from love2d") end
    client.onclose = function() print("closed") end

    function love.update()
        client:update()
    end
]]

local socket = require"socket"
local bit = require"bit"
local band, bor, bxor = bit.band, bit.bor, bit.bxor
local shl, shr = bit.lshift, bit.rshift

local OPCODE = {
    CONTINUE = 0,
    TEXT     = 1,
    BINARY   = 2,
    CLOSE    = 8,
    PING     = 9,
    PONG     = 10,
}

local STATUS = {
    CONNECTING = 0,
    OPEN       = 1,
    CLOSING    = 2,
    CLOSED     = 3,
    TCPOPENING = 4,
}

local function _callback(_) end

local _M = {
    OPCODE = OPCODE,
    STATUS = STATUS,
}
_M.__index = _M

function _M.new(host, port, path)
    local m = {
        url = {
            host = host,
            port = port,
            path = path or "/",
        },
        head = 0,
        buffer = "",
        remain = 0,
        frame = "",
        status = STATUS.TCPOPENING,
        socket = socket.tcp(),
        onopen = _callback,
        onmessage = _callback,
        onerror = print,
        onclose = _callback,
    }
    m.socket:settimeout(0)
    m.socket:connect(host, port)
    setmetatable(m, _M)
    return m
end

local mask_key = {1, 14, 5, 14}
local function send(sock, opcode, message)
    -- message type
    sock:send(string.char(bor(0x80, opcode)))

    -- empty message
    if not message then
        sock:send(string.char(0x80, unpack(mask_key)))
        return 0
    end

    -- message length
    local length = #message
    if length>65535 then
        sock:send(string.char(bor(127, 0x80),
            0, 0, 0, 0,
            band(shr(length, 24), 0xff),
            band(shr(length, 16), 0xff),
            band(shr(length, 8), 0xff),
            band(length, 0xff)))
    elseif length>125 then
        sock:send(string.char(bor(126, 0x80),
            band(shr(length, 8), 0xff),
            band(length, 0xff)))
    else
        sock:send(string.char(bor(length, 0x80)))
    end

    -- message
    sock:send(string.char(unpack(mask_key)))
    local msgbyte = {message:byte(1, length)}
    for i = 1, length do
        msgbyte[i] = bxor(msgbyte[i], mask_key[(i-1)%4+1])
    end
    return sock:send(string.char(unpack(msgbyte)))
end

local function read(ws)
    local sock = ws.socket
    local res, err, part
    if ws.remain>0 then
        local res, err, part = sock:receive(ws.remain)
        if part then
            -- still some bytes remaining
            ws.buffer, ws.remain = ws.buffer..part, ws.remain-#part
            return nil, nil, "pending"
        else
            -- all parts recieved
            ws.buffer, ws.remain = ws.buffer..res, 0
            return ws.buffer, ws.head, nil
        end
    end
    -- byte 0-1
    res, err = sock:receive(2)
    if err then return res, nil, err end
    local head = res:byte()
    -- Moved to _M:update
    -- local flag_FIN = res:byte()>=0x80
    -- local flag_MASK = res:byte(2)>=0x80
    local byte = res:byte(2)
    local length = band(byte, 0x7f)
    if length==126 then
        res = sock:receive(2)
        local b1, b2 = res:byte(1, 2)
        length = shl(b1, 8) + b2
    elseif length==127 then
        res = sock:receive(8)
        local b = {res:byte(1, 8)}
        length = shl(b[5], 24) + shl(b[6], 16) + shl(b[7], 8) + b[8]
    end
    res, err, part = sock:receive(length)
    if part then
        -- incomplete frame
        ws.head = head
        ws.buffer, ws.remain = part, length-#part
        return nil, nil, "pending"
    else
        -- complete frame
        return res, head, err
    end
end

function _M:send(message)
    send(self.socket, OPCODE.TEXT, message)
end

function _M:ping(message)
    send(self.socket, OPCODE.PING, message)
end

function _M:pong(message)
    send(self.socket, OPCODE.PONG, message)
end

local seckey = "osT3F7mvlojIvf3/8uIsJQ=="
function _M:update()
    local sock = self.socket
    if self.status==STATUS.TCPOPENING then
        local res, err = sock:connect("", 0)
        if err=="already connected" then
            local url = self.url
            sock:send(
"GET "..url.path.." HTTP/1.1\r\n"..
"Host: "..url.host..":"..url.port.."\r\n"..
"Connection: Upgrade\r\n"..
"Upgrade: websocket\r\n"..
"Sec-WebSocket-Version: 13\r\n"..
"Sec-WebSocket-Key: "..seckey.."\r\n\r\n")
            self.status = STATUS.CONNECTING
        elseif err=="Cannot assign requested address" then
            self.onerror("TCP connection failed.")
            self.status = STATUS.CLOSED
        end
    elseif self.status==STATUS.CONNECTING then
        local res, err = sock:receive("*l")
        if res then
            repeat res, err = sock:receive("*l") until res==""
            self.onopen()
            self.status = STATUS.OPEN
        end
    elseif self.status==STATUS.OPEN or self.status==STATUS.CLOSING then
        while true do
            local res, head, err = read(self)
            if err=="timeout" then
                return
            elseif err=="pending" then
                return
            elseif err=="closed" then
                self.onerror("Connection closed unexpectedly.")
                self.onclose()
                self.status = STATUS.CLOSED
                return
            end
            local code = band(head, 0x0f)
            local fin = band(head, 0x80)==0x80
            if code==OPCODE.CLOSE then
                sock:close()
                self.onclose()
                self.status = STATUS.CLOSED
            elseif code==OPCODE.PING then self:pong(res)
            elseif code==OPCODE.CONTINUE then
                self.frame = self.frame..res
                if fin then self.onmessage(self.frame) end
            else
                if fin then self.onmessage(res) else self.frame = res end
            end
        end
    end
end

function _M:close(message)
    send(self.socket, OPCODE.CLOSE, message)
    self.status = STATUS.CLOSING
end

return _M
