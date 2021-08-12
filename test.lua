package.preload["socket"] = function()end
local ws = require"websocket"
local client = {
    socket = {},
    _buffer = "",
    _length = 2,
    _head = nil,
}
local res, head, err
local function receive(t)
    return function(_, n)
        if #t>0 then
            local ret = t[1]
            if n<#ret then
                ret, t[1] = ret:sub(1,n), ret:sub(n+1)
            else
                table.remove(t, 1)
            end
            return ret, nil, nil
        else
            return nil, "timeout", nil
        end
    end
end

--空消息
client.socket.receive = receive{"\x81", "\x00"}
res, head, err = ws.read(client)
assert(res==nil and head==nil and err=="buffer length less than 2")
res, head, err = ws.read(client)
assert(res=="" and head==0x81 and err==nil)

--1字节消息
client.socket.receive = receive{"\x81\x01"}
res, head, err = ws.read(client)
assert(res==nil and head==nil and err==nil)
client.socket.receive = receive{"\x31"}
res, head, err = ws.read(client)
assert(res=="1" and head==0x81 and err==nil)

--5字节消息
client.socket.receive = receive{"\x81\x05", "12", "345"}
res, head, err = ws.read(client)
assert(res==nil and head==nil and err=="buffer length less than 5")
res, head, err = ws.read(client)
assert(res=="12345" and head==0x81 and err==nil)

--200字节消息
local s = "" for i=1,100 do s=s..i%5 end
client.socket.receive = receive{"\x81\x7e", "\x00", "\xc8", s, s}
res, head, err = ws.read(client)
assert(res==nil and head==nil and err=="buffer length less than 4")
res, head, err = ws.read(client)
assert(res==nil and head==nil and err=="buffer length less than 200")
res, head, err = ws.read(client)
assert(res==s..s and head==0x81 and err==nil)

print(ws.read(client))
