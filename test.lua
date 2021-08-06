local band, bor, bxor = bit.band, bit.bor, bit.bxor
local shl, shr = bit.lshift, bit.rshift

local function check(ws)
    if #ws._buffer<2 then
        return nil, nil, "buffer length less than 2"
    end
    local length = band(ws._buffer:byte(2), 0x7f)
    if length==126 then
        if #ws._buffer<4 then
            return nil, nil, "buffer length less than 4"
        end
        local b1, b2 = ws._buffer:byte(3, 4)
        ws._expect = 2 + shl(b1, 8) + b2
    elseif length==127 then
        if #ws._buffer<10 then
            return nil, nil, "[test] buffer length less than 10"
        end
        local b5, b6, b7, b8 = ws._buffer:byte(7, 10)
        ws._expect = 2 + shl(b5, 24) + shl(b6, 16) + shl(b7, 8) + b8
    else
        ws._expect = 2 + length
    end
    if #ws._buffer>=ws._expect then
        return ws._buffer:sub(3), ws._buffer:byte(1), nil
    else
        return nil, nil, "[test] buffer length less than "..ws._expect
    end
end

print(check{_expect=2,_buffer="\x81"})
print(check{_expect=2,_buffer="\x81\x00"})
print(check{_expect=3,_buffer="\x81\x01"})
print(check{_expect=3,_buffer="\x81\x01\x30"})
print(check{_expect=2,_buffer="\x81\x7e"})
print(check{_expect=2,_buffer="\x81\x7f"})
print(check{_expect=2,_buffer="\x81\x7e\x01\x02"})
print(check{_expect=2,_buffer="\x81\x7f\x00\x00\x00\x00\x00\x01\xbf\x50"})
