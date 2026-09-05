-- SRun's browser-compatible encoding, using OpenWrt's existing nixio.bit.
-- Standalone module; no network, files or credentials are logged here.
return function(bit)
    local M, U = {}, 4294967296
    local function norm(x) return x % U end
    local function band(a,b) return norm(bit.band(a,b)) end
    local function bxor(a,b) return norm(bit.bxor(a,b)) end
    local function bor(a,b) return norm(bit.bor(a,b)) end
    local function bnot(a) return norm(bit.bnot(a)) end
    local function rshift(a,n) return norm(bit.rshift(a,n)) end
    local function lshift(a,n) return (a % 2^(32-n)) * 2^n end
    local function rol(a,n) return bor(lshift(a,n),rshift(a,32-n)) end
    local function le(x)
        return string.char(x%256,math.floor(x/256)%256,math.floor(x/65536)%256,math.floor(x/16777216)%256)
    end
    local function be(x) return le(x):reverse() end
    local function word(s,i,little)
        local a,b,c,d=s:byte(i,i+3)
        if little then return a+b*256+c*65536+d*16777216 end
        return d+c*256+b*65536+a*16777216
    end
    local function hex(s) return (s:gsub('.',function(c) return string.format('%02x',c:byte()) end)) end
    local function pad(s,little)
        local bits=#s*8
        local lo,hi=bits%U,math.floor(bits/U)
        return s..'\128'..string.rep('\0',(55-#s)%64)..(little and le(lo)..le(hi) or be(hi)..be(lo))
    end
    local shifts={7,12,17,22,5,9,14,20,4,11,16,23,6,10,15,21}
    local constants={}
    for i=1,64 do constants[i]=math.floor(math.abs(math.sin(i))*U) end
    function M.md5raw(s)
        s=pad(s,true)
        local a0,b0,c0,d0=0x67452301,0xefcdab89,0x98badcfe,0x10325476
        for start=1,#s,64 do
            local w={}
            for j=0,15 do w[j]=word(s,start+j*4,true) end
            local a,b,c,d=a0,b0,c0,d0
            for j=0,63 do
                local f,g,round
                if j<16 then f=bor(band(b,c),band(bnot(b),d)); g=j; round=0
                elseif j<32 then f=bor(band(d,b),band(bnot(d),c)); g=(5*j+1)%16; round=1
                elseif j<48 then f=bxor(bxor(b,c),d); g=(3*j+5)%16; round=2
                else f=bxor(c,bor(b,bnot(d))); g=(7*j)%16; round=3 end
                local nextb=norm(b+rol(norm(a+f+constants[j+1]+w[g]),shifts[round*4+j%4+1]))
                a,d,c,b=d,c,b,nextb
            end
            a0,b0,c0,d0=norm(a0+a),norm(b0+b),norm(c0+c),norm(d0+d)
        end
        return le(a0)..le(b0)..le(c0)..le(d0)
    end
    function M.md5(s) return hex(M.md5raw(s)) end
    function M.hmac_md5(key,s)
        if #key>64 then key=M.md5raw(key) end
        key=key..string.rep('\0',64-#key)
        local inner,outer={},{}
        for i=1,64 do inner[i]=string.char(bxor(key:byte(i),0x36)); outer[i]=string.char(bxor(key:byte(i),0x5c)) end
        return hex(M.md5raw(table.concat(outer)..M.md5raw(table.concat(inner)..s)))
    end
    function M.sha1(s)
        s=pad(s,false)
        local h0,h1,h2,h3,h4=0x67452301,0xefcdab89,0x98badcfe,0x10325476,0xc3d2e1f0
        for start=1,#s,64 do
            local w={}
            for j=0,15 do w[j]=word(s,start+j*4,false) end
            for j=16,79 do w[j]=rol(bxor(bxor(w[j-3],w[j-8]),bxor(w[j-14],w[j-16])),1) end
            local a,b,c,d,e=h0,h1,h2,h3,h4
            for j=0,79 do
                local f,k
                if j<20 then f=bor(band(b,c),band(bnot(b),d)); k=0x5a827999
                elseif j<40 then f=bxor(bxor(b,c),d); k=0x6ed9eba1
                elseif j<60 then f=bor(bor(band(b,c),band(b,d)),band(c,d)); k=0x8f1bbcdc
                else f=bxor(bxor(b,c),d); k=0xca62c1d6 end
                local t=norm(rol(a,5)+f+e+k+w[j])
                e,d,c,b,a=d,c,rol(b,30),a,t
            end
            h0,h1,h2,h3,h4=norm(h0+a),norm(h1+b),norm(h2+c),norm(h3+d),norm(h4+e)
        end
        return hex(be(h0)..be(h1)..be(h2)..be(h3)..be(h4))
    end
    local function units(s)
        local out,i={},1
        while i<=#s do
            local a=s:byte(i); local c,n=a,1
            if a>=240 then c=(a-240)*262144+(s:byte(i+1)-128)*4096+(s:byte(i+2)-128)*64+s:byte(i+3)-128; n=4
            elseif a>=224 then c=(a-224)*4096+(s:byte(i+1)-128)*64+s:byte(i+2)-128; n=3
            elseif a>=192 then c=(a-192)*64+s:byte(i+1)-128; n=2 end
            if c>65535 then c=c-65536; out[#out+1]=0xd800+math.floor(c/1024); out[#out+1]=0xdc00+c%1024
            else out[#out+1]=c end
            i=i+n
        end
        return out
    end
    local function words(s,length)
        local u,v=units(s),{}
        for i=1,#u,4 do
            v[#v+1]=bor(bor(u[i],lshift(u[i+1] or 0,8)),bor(lshift(u[i+2] or 0,16),lshift(u[i+3] or 0,24)))
        end
        if length then v[#v+1]=#u end
        return v
    end
    local function mix(z,y,total,key)
        return norm(bxor(rshift(z,5),lshift(y,2))+bxor(bxor(rshift(y,3),lshift(z,4)),bxor(total,y))+bxor(key,z))
    end
    function M.xencode(s,token)
        if s=='' then return '' end
        local v,k=words(s,true),words(token,false)
        for i=#k+1,4 do k[i]=0 end
        local n=#v; local z,total=v[n],0
        for _=1,math.floor(6+52/n) do
            total=norm(total+0x9e3779b9)
            local e=band(rshift(total,2),3)
            for p=1,n-1 do
                v[p]=norm(v[p]+mix(z,v[p+1],total,k[bxor((p-1)%4,e)+1])); z=v[p]
            end
            v[n]=norm(v[n]+mix(z,v[1],total,k[bxor((n-1)%4,e)+1])); z=v[n]
        end
        local out={}
        for i=1,n do out[i]=le(v[i]) end
        return table.concat(out)
    end
    local alpha='LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA'
    local function b64(s)
        local out={}
        for i=1,#s,3 do
            local a,b,c=s:byte(i,i+2)
            local x=a*65536+(b or 0)*256+(c or 0)
            local p,q,r,t=math.floor(x/262144)%64,math.floor(x/4096)%64,math.floor(x/64)%64,x%64
            out[#out+1]=alpha:sub(p+1,p+1)..alpha:sub(q+1,q+1)..(b and alpha:sub(r+1,r+1) or '=')..(c and alpha:sub(t+1,t+1) or '=')
        end
        return table.concat(out)
    end
    local escapes={['\b']='\\b',['\f']='\\f',['\n']='\\n',['\r']='\\r',['\t']='\\t',['"']='\\"',['\\']='\\\\'}
    local function quote(s)
        return '"'..s:gsub('[%z\1-\31\\"]',function(c) return escapes[c] or string.format('\\u%04x',c:byte()) end)..'"'
    end
    function M.params(username,password,ip,acid,token)
        acid=tostring(acid)
        local plain='{"username":'..quote(username)..',"password":'..quote(password)..',"ip":'..quote(ip)..',"acid":'..quote(acid)..',"enc_ver":"srun_bx1"}'
        local info='{SRBX1}'..b64(M.xencode(plain,token))
        local digest=M.hmac_md5(token,password)
        local sum=token..username..token..digest..token..acid..token..ip..token..'200'..token..'1'..token..info
        return {action='login',username=username,password='{MD5}'..digest,os='Linux',name='Linux',double_stack='0',
                chksum=M.sha1(sum),info=info,ac_id=acid,ip=ip,n='200',type='1'}
    end
    return M
end
