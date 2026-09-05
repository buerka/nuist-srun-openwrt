-- OpenWrt's nixio, LuaBitOp, or a native Lua 5.3+ adapter for offline tests.
local ok,n=pcall(require,'nixio')
if ok then return n.bit end
local found,b=pcall(require,'bit')
if found then return b end
local native=assert(load([[
return {
    band=function(a,b) return (math.floor(a)&math.floor(b))&0xffffffff end,
    bor=function(a,b) return (math.floor(a)|math.floor(b))&0xffffffff end,
    bxor=function(a,b) return (math.floor(a)~math.floor(b))&0xffffffff end,
    bnot=function(a) return (~math.floor(a))&0xffffffff end,
    lshift=function(a,b) return (math.floor(a)<<b)&0xffffffff end,
    rshift=function(a,b) return (math.floor(a)&0xffffffff)>>b end
}
]]))()
return native
