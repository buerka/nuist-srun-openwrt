-- Exercises the real client with in-memory files and HTTP responses.
-- No network calls, real credentials or system configuration are accessed.
local bit=dofile('tests/bit.lua')
local saved={open=io.open,popen=io.popen,print=print,exit=os.exit,remove=os.remove,time=os.time}
local function online(user)
    return {error='ok',user_name=user or 'demo',domain='campus',online_ip='192.0.2.20'}
end
local offline={error='not_online_error'}
local token={error='ok',challenge='0123456789abcdef0123456789abcdef',client_ip='192.0.2.20'}
local count=0
local function scenario(name,options)
    local config={portal='http://192.0.2.1',ac_id='1',username='demo@campus',password='canary-password',interval=60}
    for k,v in pairs(options.config or {}) do config[k]=v end
    local mem,output,requests={['/test/config.json']='CONFIG'},{},{}
    local urls={}; local request_count=0; local current_request
    local mode=options.mode or 600
    package.loaded.nixio=nil; package.loaded['nixio.fs']=nil; package.loaded['luci.jsonc']=nil
    package.preload.nixio=function() return {
        bit=bit,getpid=function() return 1234 end,nanosleep=function() end,
        open=function(_,_,permissions)
            assert(permissions=='600')
            return {lock=function() return not options.locked end,close=function() end}
        end
    } end
    package.preload['nixio.fs']=function() return {
        stat=function() return {type='reg',modedec=mode} end,
        mkdir=function(_,permissions) assert(permissions=='700'); return true end,
        chmod=function(_,permissions) assert(permissions=='600'); return true end,
        rmdir=function() return true end
    } end
    package.preload['luci.jsonc']=function() return {parse=function(text)
        if text=='CONFIG' then return config end
        local index=text:match('^RESPONSE(%d+)$')
        return index and options.responses[tonumber(index)] or nil
    end} end
    io.open=function(path,modearg)
        if modearg=='r' then return {read=function() return mem[path] end,close=function() end} end
        local f={}
        function f:write(...)
            mem[path]=table.concat({...})
            current_request=mem[path]
        end
        function f:close() end
        return f
    end
    io.popen=function(command)
        assert(not command:find(config.password,1,true),'secret leaked to argv')
        assert(not command:find('192.0.2.1',1,true),'authentication URL leaked to argv')
        assert(not command:find('%-%-location'),'redirect following enabled')
        assert(command:find('%-%-noproxy'),'proxy environment must be disabled')
        request_count=request_count+1
        requests[#requests+1]=command; urls[#urls+1]=current_request
        local index=request_count
        return {read=function() return options.bad_body or ('nuist_client(RESPONSE'..index..')') end,close=function() end}
    end
    os.time=function() return 1234567890 end
    os.remove=function(path) mem[path]=nil; return true end
    print=function(value) output[#output+1]=tostring(value) end
    os.exit=function(code) error({exit_code=code},0) end
    arg={[0]='src/srun.lua',[1]=options.action or 'once',[2]='/test/config.json'}
    local _,result=pcall(dofile,'src/srun.lua')
    io.open=saved.open; io.popen=saved.popen; print=saved.print
    os.exit=saved.exit; os.remove=saved.remove; os.time=saved.time
    assert(type(result)=='table' and result.exit_code==options.exit,name..': unexpected exit')
    assert(request_count==#options.responses,name..': unexpected request count')
    local logs=table.concat(output,'\n')
    assert(logs==options.output,name..': unexpected output: '..logs)
    assert(not logs:find('canary-password',1,true),name..': secret leaked to logs')
    assert(not logs:find(token.challenge,1,true),name..': challenge leaked to logs')
    for path in pairs(mem) do assert(path=='/test/config.json',name..': temporary request was not removed') end
    if options.login then
        assert(urls[3]:find('ip=192.0.2.20',1,true),'must use server-discovered IP')
        assert(urls[3]:find('username=demo%40campus',1,true),'domain suffix lost')
        assert(urls[3]:find('password=%7BMD5%7D',1,true),'incorrect login scheme')
    end
    count=count+1
end
scenario('online is a no-op',{responses={online()},exit=0,output='online'})
scenario('offline login verified',{responses={offline,token,{error='ok'},online()},exit=0,output='login_verified',login=true})
scenario('other account',{responses={online('someone-else')},exit=1,output='other_account; login_skipped'})
scenario('unknown status',{responses={{error='unexpected'}},exit=1,output='unknown_status; login_skipped'})
scenario('invalid response',{responses={{}},bad_body='not-json',exit=1,output='invalid_portal_response'})
scenario('empty HTTP body',{responses={{}},bad_body='',exit=1,output='portal_unreachable'})
scenario('login rejection',{responses={offline,token,{error='fail',ecode='E2901',error_msg='canary-password'}},exit=1,output='login_rejected; code=E2901',login=true})
scenario('missing server IP',{responses={offline,{error='ok',challenge=token.challenge}},exit=1,output='challenge_missing_client_ip'})
scenario('challenge rejection',{responses={offline,{error='fail'}},exit=1,output='challenge_rejected'})
scenario('post-login remains offline',{responses={offline,token,{error='ok'},offline,offline,offline},exit=1,output='login_not_verified',login=true})
scenario('unsafe config mode',{responses={},mode=644,exit=1,output='config_requires_mode_0600'})
scenario('empty password',{responses={},config={password=''},exit=1,output='credentials_missing'})
scenario('invalid origin',{responses={},config={portal='http://user:pass@example.test/path'},exit=1,output='invalid_portal_origin'})
scenario('invalid interval',{responses={},config={interval='bad'},exit=1,output='invalid_interval'})
scenario('lock contention',{responses={},locked=true,exit=1,output='another_check_running'})
scenario('local configuration check',{responses={},action='check',exit=0,output='config_ok'})
scenario('interval clamped',{responses={},config={interval=1},action='interval',exit=0,output='30'})
scenario('custom interface',{responses={},config={interface='wwan'},action='interface',exit=0,output='wwan'})
scenario('invalid interface',{responses={},config={interface='wan;id'},action='interface',exit=1,output='invalid_interface'})
scenario('HTTPS origin',{responses={online()},config={portal='https://portal.example.test:8443/'},exit=0,output='online'})
print('PASS: '..count..' offline client scenarios')
