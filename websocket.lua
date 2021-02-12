local socket = require"socket"
local bit = require"bit"
local band = bit.band
local bor = bit.bor
local bxor = bit.bxor
local shl = bit.lshift
local shr = bit.rshift

local log_debug = print
local b2s = function(b)return b and"true"or"false"end

local OPCODES = {
    ["CONTINUE"]=0,
    ["TEXT"]    =1,
    ["BINARY"]  =2,
    ["CLOSE"]   =8,
    ["PING"]    =9,
    ["PONG"]    =10,
}

local _M = {
    OPCODES = OPCODES,
}
_M.__index = _M

_M.new = function()
    local m = {}
    setmetatable(m, _M)
    return m
end

_M.connect = function(self, host, port)
    local socket = socket.tcp()
    self.socket = socket
    local res, err = socket:connect(host, port)
    log_debug("[handshake] connected")
    if res~=1 then
        return res, err
    end
    -- WebSocket握手
    res, err = socket:send("GET / HTTP/1.1\r\nHost: "..host..":"..port.."\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: osT3F7mvlojIvf3/8uIsJQ==\r\n\r\n")
    repeat
        res = socket:receive("*l")
    until res==""
    log_debug("[handshake] succeed")
end

_M.send = function(self, message)
    local socket = self.socket
    local mask_key = {1, 14, 5, 14}
    -- 消息类型
    socket:send(string.char(bor(0x80, OPCODES.BINARY)))
    -- 编码长度
    local length = #message
    log_debug("[encode] message length: "..length)
    if length>65535 then
        socket:send(string.char(bor(127, 0x80), 0, 0, 0, 0,
            band(shr(length, 24), 0xff),
            band(shr(length, 16), 0xff),
            band(shr(length, 8), 0xff),
            band(length, 0xff)))
    elseif length>125 then
        socket:send(string.char(bor(126, 0x80),
            band(shr(length, 8), 0xff),
            band(length, 0xff)))
    else
        socket:send(string.char(bor(length, 0x80)))
    end
    log_debug("[encode] masking")
    socket:send(string.char(unpack(mask_key)))
    local msgbyte = {message:byte(1, length)}
    for i = 1, length do
        msgbyte[i] = bxor(msgbyte[i], mask_key[(i-1)%4+1])
    end
    socket:send(string.char(unpack(msgbyte)))
    log_debug("[encode] end")
end

_M.read = function(self)
    -- 解码数据
    -- 0-1字节
    local socket = self.socket
    local res, err = socket:receive(2)
    if res==nil then
        return res, err
    end
    local byte = res:byte()
    local flag_FIN = byte>=0x80
    local OPCODE = band(byte, 0x0f)
    byte = res:byte(2)
    local flag_MASK = byte>=0x80
    log_debug("[decode] FIN="..b2s(flag_FIN)..", OPCODE="..OPCODE..", MASK="..b2s(flag_MASK))
    -- 解码长度
    local length = band(byte, 0x7f)
    if length==126 then
        res = socket:receive(2)
        local b1, b2 = res:byte(1, 2)
        length = shl(b1, 8) + b2
    elseif length==127 then
        res = socket:receive(8)
        local b = {res:byte(1, 8)}
        length = shl(b[5], 32) + shl(b[6], 24) + shl(b[7], 8) + b[8]
    end
    log_debug("[decode] message length: "..length)
    -- 接收数据
    res = socket:receive(length)
    log_debug("[decode] string length: "..#res)
    log_debug("[decode] end")
    return res
end

_M.close = function(self)
    self.socket:close()
end

_M.settimeout = function(self, t)
    self.socket:settimeout(t)
end

return _M
