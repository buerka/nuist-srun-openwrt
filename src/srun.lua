#!/usr/bin/lua
-- SRun IPv4 client. Requires Lua, nixio, luci.jsonc and curl.
local nixio=require('nixio')
local fs=require('nixio.fs')
local json=require('luci.jsonc')
local directory=arg[0]:match('^(.*)/') or '.'
local crypto=dofile(directory..'/srun_crypto.lua')(nixio.bit)
local action=arg[1] or 'status'
local configpath=arg[2] or '/etc/nuist-srun.json'
local temporary,lock
local function fail(message) error({public_message=message},0) end
local function read(path)
    local f=io.open(path,'r'); if not f then return nil end
    local value=f:read('*a'); f:close(); return value
end
local function sq(s) return "'"..s:gsub("'","'\\''").."'" end
local function pct(s)
    return (tostring(s):gsub('([^A-Za-z0-9_.~-])',function(c) return string.format('%%%02X',c:byte()) end))
end
local function parse(s)
    s=s:match('^%s*(.-)%s*$')
    if s:sub(1,1)~='{' then s=s:match('^[%w_$%.]+%s*%((.*)%)%s*;?$') end
    local value=s and json.parse(s)
    if type(value)~='table' then fail('invalid_portal_response') end
    return value
end
local function ipv4(ip)
    if type(ip)~='string' then return false end
    local a,b,c,d=ip:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
    return a and tonumber(a)<256 and tonumber(b)<256 and tonumber(c)<256 and tonumber(d)<256
end
local function origin(value)
    if type(value)~='string' then return nil end
    value=value:gsub('/$','')
    local scheme,authority=value:match('^(https?)://([^/]+)$')
    if not scheme then return nil end
    local host,port=authority:match('^([A-Za-z0-9][A-Za-z0-9.%-]*):(%d+)$')
    if port and (tonumber(port)<1 or tonumber(port)>65535) then return nil end
    host=host or authority:match('^([A-Za-z0-9][A-Za-z0-9.%-]*)$')
    if not host or host:find('%.%.') or host:sub(-1)=='-' then return nil end
    return value
end
local function request(config,path,params)
    local query={callback='nuist_client',_=tostring(os.time())}
    for k,v in pairs(params or {}) do query[k]=v end
    local parts={}
    for k,v in pairs(query) do parts[#parts+1]=pct(k)..'='..pct(v) end
    local url=config.portal..path..'?'..table.concat(parts,'&')
    local pathconf=temporary..'/request.conf'
    local f=io.open(pathconf,'w')
    if not f then fail('cannot_write_temporary_request') end
    -- Configuration file is inside a root-only RAM directory. URL contains
    -- credentials; do not put it on curl's command line or follow redirects.
    f:write('url = "',url,'"\n'); f:close(); fs.chmod(pathconf,'600')
    local pipe=io.popen("curl --noproxy '*' --silent --fail --connect-timeout 4 --max-time 10 --max-filesize 65536 --config "..sq(pathconf).." 2>/dev/null",'r')
    if not pipe then fail('cannot_start_curl') end
    local body=pipe:read(65537) or ''; pipe:close(); os.remove(pathconf)
    if #body==0 or #body>65536 then fail('portal_unreachable') end
    return parse(body)
end
local function status(config)
    local r=request(config,'/cgi-bin/rad_user_info')
    if r.error=='ok' and r.user_name and ipv4(r.online_ip) then
        local base,domain=config.username:match('^(.-)@(.+)$')
        if r.user_name~=config.username and not (base and r.user_name==base and r.domain==domain) then
            return 'other_account',r
        end
        return 'online',r
    end
    if r.error=='not_online_error' then return 'offline',r end
    return 'unknown_status',r
end
local function main()
    local st=fs.stat(configpath)
    if not st or st.type~='reg' or tostring(st.modedec)~='600' then fail('config_requires_mode_0600') end
    local config=json.parse(read(configpath) or '')
    if type(config)~='table' then fail('invalid_config') end
    local interval=tonumber(config.interval or 60)
    if not interval or interval~=interval or interval==math.huge then fail('invalid_interval') end
    interval=math.max(30,math.min(1800,math.floor(interval)))
    local interface=config.interface or 'wan'
    if type(interface)~='string' or not interface:match('^[A-Za-z0-9_]+$') then fail('invalid_interface') end
    if action=='interval' then print(interval); return 0 end
    if action=='interface' then print(interface); return 0 end
    config.portal=origin(config.portal)
    if not config.portal then fail('invalid_portal_origin') end
    config.ac_id=tostring(config.ac_id or '')
    if not config.ac_id:match('^%d+$') or tonumber(config.ac_id)<1 then fail('invalid_ac_id') end
    if type(config.username)~='string' or config.username==''
        or type(config.password)~='string' or config.password=='' then fail('credentials_missing') end
    if action=='check' then print('config_ok'); return 0 end
    if action~='status' and action~='once' then fail('usage: srun.lua check|status|once|interval|interface [config]') end
    lock=nixio.open('/tmp/nuist-srun.lock','w','600')
    if not lock or not lock:lock('tlock') then fail('another_check_running') end
    temporary='/tmp/nuist-srun-'..tostring(nixio.getpid())
    if not fs.mkdir(temporary,'700') then fail('cannot_create_private_temporary_directory') end
    local state=status(config)
    if action=='status' then print(state); return state=='online' and 0 or 1 end
    if state=='online' then print('online'); return 0 end
    if state~='offline' then fail(state..'; login_skipped') end
    local challenge=request(config,'/cgi-bin/get_challenge',{username=config.username,ip=''})
    if challenge.error~='ok' or type(challenge.challenge)~='string' or challenge.challenge=='' then fail('challenge_rejected') end
    local ip=challenge.client_ip or challenge.online_ip
    if not ipv4(ip) then fail('challenge_missing_client_ip') end
    local params=crypto.params(config.username,config.password,ip,config.ac_id,challenge.challenge)
    local result=request(config,'/cgi-bin/srun_portal',params)
    if result.error~='ok' then
        local code=tostring(result.ecode or 'unknown')
        if not code:match('^[A-Za-z0-9_-]+$') or #code>40 then code='unknown' end
        fail('login_rejected; code='..code)
    end
    for _=1,3 do
        nixio.nanosleep(2)
        if status(config)=='online' then print('login_verified'); return 0 end
    end
    fail('login_not_verified')
end
local ok,code=pcall(main)
if temporary then os.remove(temporary..'/request.conf'); fs.rmdir(temporary) end
if lock then lock:close() end
if not ok then
    -- Only deliberately generated, nonsecret error messages are displayed.
    if type(code)=='table' and type(code.public_message)=='string' then
        print(code.public_message)
    else
        print('client_runtime_error')
    end
end
os.exit(ok and code or 1)
