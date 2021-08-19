--[[
websocket client pure lua implement for love2d
by flaribbit

usage:
    local client = require("websocket").new("127.0.0.1", 5000)
    function client:onmessage(s) print(s) end
    function client:onopen() self:send("hello from love2d") end
    function client:onclose() print("closed") end

    function love.update()
        client:update()
    end
]]

local socket = require"socket"
local bit = require"bit"
local band, bor, bxor = bit.band, bit.bor, bit.bxor
local shl, shr = bit.lshift, bit.rshift
local seckey = "osT3F7mvlojIvf3/8uIsJQ=="

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

---@class wsclient
---@field socket table
---@field url table
---@field _head integer|nil
local _M = {
    OPCODE = OPCODE,
    STATUS = STATUS,
}
_M.__index = _M
function _M:onopen() end
function _M:onmessage(message) end
function _M:onerror(error) end
function _M:onclose(code, reason) end

---create websocket connection
---@param host string
---@param port integer
---@param path string
---@return wsclient
function _M.new(host, port, path)
    local m = {
        url = {
            host = host,
            port = port,
            path = path or "/",
        },
        _continue = "",
        _buffer = "",
        _length = 0,
        _head = nil,
        status = STATUS.TCPOPENING,
        socket = socket.tcp(),
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

---read a message
---@return string|nil res message
---@return number|nil head websocket frame header
---@return string|nil err error message
function _M:read()
    local res, err, part
    ::RECIEVE::
    res, err, part = self.socket:receive(self._length-#self._buffer)
    if err=="closed" then return nil, nil, err end
    if part or res then
        self._buffer = self._buffer..(part or res)
    else
        return nil, nil, nil
    end
    if not self._head then
        if #self._buffer<2 then
            return nil, nil, "buffer length less than 2"
        end
        local length = band(self._buffer:byte(2), 0x7f)
        if length==126 then
            if self._length==2 then self._length = 4 goto RECIEVE end
            if #self._buffer<4 then
                return nil, nil, "buffer length less than 4"
            end
            local b1, b2 = self._buffer:byte(3, 4)
            self._length = shl(b1, 8) + b2
        elseif length==127 then
            if self._length==2 then self._length = 10 goto RECIEVE end
            if #self._buffer<10 then
                return nil, nil, "buffer length less than 10"
            end
            local b5, b6, b7, b8 = self._buffer:byte(7, 10)
            self._length = shl(b5, 24) + shl(b6, 16) + shl(b7, 8) + b8
        else
            self._length = length
        end
        self._head, self._buffer = self._buffer:byte(1), ""
        if length>0 then goto RECIEVE end
    end
    if #self._buffer>=self._length then
        local ret, head = self._buffer, self._head
        self._length, self._buffer, self._head = 2, "", nil
        return ret, head, nil
    else
        return nil, nil, "buffer length less than "..self._length
    end
end

---send a message
---@param message string
function _M:send(message)
    send(self.socket, OPCODE.TEXT, message)
end

---send a ping message
---@param message string
function _M:ping(message)
    send(self.socket, OPCODE.PING, message)
end

---send a pong message (no need)
---@param message any
function _M:pong(message)
    send(self.socket, OPCODE.PONG, message)
end

---update client status
function _M:update()
    local sock = self.socket
    if self.status==STATUS.TCPOPENING then
        local url = self.url
        local _, err = sock:connect(url.host, url.port)
        self._length = self._length+1
        if err=="already connected" then
            sock:send(
"GET "..url.path.." HTTP/1.1\r\n"..
"Host: "..url.host..":"..url.port.."\r\n"..
"Connection: Upgrade\r\n"..
"Upgrade: websocket\r\n"..
"Sec-WebSocket-Version: 13\r\n"..
"Sec-WebSocket-Key: "..seckey.."\r\n\r\n")
            self.status = STATUS.CONNECTING
            self._length = 2
        elseif self._length>600 then
            self:onerror("connection failed")
            self.status = STATUS.CLOSED
        end
    elseif self.status==STATUS.CONNECTING then
        local res = sock:receive("*l")
        if res then
            repeat res = sock:receive("*l") until res==""
            self:onopen()
            self.status = STATUS.OPEN
        end
    elseif self.status==STATUS.OPEN or self.status==STATUS.CLOSING then
        while true do
            local res, head, err = self:read()
            if err=="closed" then
                self.status = STATUS.CLOSED
                return
            elseif res==nil then
                return
            end
            local opcode = band(head, 0x0f)
            local fin = band(head, 0x80)==0x80
            if opcode==OPCODE.CLOSE then
                if res~="" then
                    local code = shl(res:byte(1), 8) + res:byte(2)
                    self:onclose(code, res:sub(3))
                else
                    self:onclose(1005, "")
                end
                sock:close()
                self.status = STATUS.CLOSED
            elseif opcode==OPCODE.PING then self:pong(res)
            elseif opcode==OPCODE.CONTINUE then
                self._continue = self._continue..res
                if fin then self:onmessage(self._continue) end
            else
                if fin then self:onmessage(res) else self._continue = res end
            end
        end
    end
end

---close websocket connection
---@param code integer|nil
---@param message string|nil
function _M:close(code, message)
    if code and message then
        send(self.socket, OPCODE.CLOSE, string.char(shr(code, 8), band(code, 0xff))..message)
    else
        send(self.socket, OPCODE.CLOSE, nil)
    end
    self.status = STATUS.CLOSING
end

return _M
