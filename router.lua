router={INIT=0,JOINING=1,JOINED=2,CONFIGURED=3,CONFIGURED_FIXED=4,client_by_ssid={},client_by_mac={},errors=0}
wifi.mode(wifi.STATIONAP)
wifi.start()

function mprint(...)
  print(wifi.ap.getmac(),...)
end

function router.ap_on(event, info)
  mprint("router.ap_on",event)
end

function serialize_list (tabl)
    local str = ''
    local fsep = ''
    local sep = ','
    for key, value in pairs (tabl) do
	if (tonumber(key)) then
	  str = str..fsep..'['..key..']='
        else
	  str = str..fsep..key..'='
	end
        if type (value) == "table" then
            str = str..'{'..serialize_list (value,sep) .. '}' 
        else
            str = str.."'"..tostring(value).."'"
        end
	fsep=sep
    end
    return str
end

-- https://stackoverflow.com/questions/8200228/how-can-i-convert-an-ip-address-into-an-integer-with-lua/8200301
--
function ip2dec(ip) local i, dec = 3, 0; for d in string.gmatch(ip, "%d+") do dec = dec + 2 ^ (8 * i) * d; i = i - 1 end; return dec end

function dec2ip(decip) local divisor, quotient, ip; for i = 3, 0, -1 do divisor = 2 ^ (i * 8); quotient, decip = math.floor(decip / divisor), math.fmod(decip, divisor); if nil == ip then ip = quotient else ip = ip .. "." .. quotient end end return ip end


function router.table_parse(str)
   return load("return {"..str.."}")()
end

function router.send_info()
  mprint("sending ping to ",router.gw)
  router.socket:send(9999,router.gw,serialize_list({command="ping",mac=wifi.ap.getmac(),ssid=router.ssid}))
end

function router.get_client_data_by_id(data)
  local iplen=(router.maxip-router.minip+1-256)/data.maxclients
  local minip=router.minip+256+(data.idx-1)*iplen
  local maxip=minip+iplen-1
  -- print("iplen",iplen,dec2ip(router.maxip),dec2ip(router.minip),dec2ip(minip),dec2ip(maxip))
  return{idx=data.idx,ssid=data.ssid,minip=dec2ip(minip),maxip=dec2ip(maxip)}
end

function router.get_client_data(request)
  local level=router.depth(router.ssid)
  local maxclients=router.topology[level+1]
  if (router.client_by_mac[request.mac]) then
    return router.get_client_data_by_id(router.client_by_mac[request.mac])
  end
  for i=1,maxclients do
    local ssid=router.ssid..'-'..i
    if (not router.client_by_ssid[ssid]) then
      router.client_by_ssid[ssid]=request.mac
      router.client_by_mac[request.mac]={ssid=ssid,idx=i,maxclients=maxclients}
      return router.get_client_data_by_id(router.client_by_mac[request.mac])
    end
  end
  mprint("maxclients",maxclients,"reached",request.mac)
  return nil
end

function router.udp_on(s, data, port, ip)
  -- mprint("router.udp_on",data,port,ip)
  local request=router.table_parse(data)
  mprint("got",request.command,"from",ip)
  if (request.command == 'ping') then
    -- mprint("ping",request.mac, ip, port)
    if (router.topology) then
      local data=router.get_client_data(request)
      data.command='pong'
      data.topology=router.topology
      reply=serialize_list(data)
      mprint("sending pong to ",router.ssid,ip,reply)
      router.socket:send(port,ip,reply)
    end
  end
  if (request.command == 'pong' and router.state == router.JOINED) then
    -- mprint("pong", ip, port, request.topology[1])
    if (not router.topology or table.concat(router.topology,',') ~= table.concat(request.topology,',')) then
      mprint("new topology",table.concat(request.topology,','));
      router.topology=request.topology
    end
    if (not router.ssid or request.ssid ~= router.ssid) then
      mprint("new ssid",request.ssid);
      router.ssid=request.ssid
      router.client_by_ssid={}
      router.client_by_mac={}
    end
    mprint("ip range",request.minip,"-",request.maxip)
    if (router.state == router.JOINED) then
      wifi.ap.config{ssid=request.ssid,channel=router.ap.channel}
      router.minip=ip2dec(request.minip)
      router.maxip=ip2dec(request.maxip)
      local ip=dec2ip(router.minip+1)
      wifi.ap.setip{ip=ip,netmask='255.255.255.0',gw=ip}
      router.ap_ip=ip
      router.state=router.CONFIGURED
      router.errors=0
    end
  end
end

function router.sta_on(event, info)
  if (event == 'got_ip') then
    router.state=router.JOINED
    mprint("router.sta_on",event,info.ip,info.netmask,info.gw)
    router.sta_ip=info.ip
    router.gw=info.gw
    router.send_info()
    local bytes={}
    for byte in string.gmatch(info.ip, "[^.]+") do
      table.insert(bytes, tonumber(byte))
    end
  else
    mprint("router.sta_on",event)
  end
end

function router.depth(ssid)
   if (string.sub(ssid,0,7) == 'ESPMESH') then
     local _,count=string.gsub(ssid,'-','')
     return count
   end
   return -1
end

function router.preference(ap)
   local depth=router.depth(ap.ssid)
   if (depth == -1) then return 0 end
   return 1000-depth*20+ap.rssi
end

function router.scan_results(err,arr)
  if err then
    mprint ("Scan failed:", err)
  else
    local best_pref=0
    local best
    mprint(string.format("%-26s","SSID"),"Channel BSSID              RSSI Auth Bandwidth Pref")
    for i,ap in ipairs(arr) do
      pref=router.preference(ap)
      mprint(string.format("%-32s",ap.ssid),ap.channel,ap.bssid,ap.rssi,ap.auth,ap.bandwidth,pref)
      if (pref > best_pref) then
         best=ap
	 best_pref=pref
      end
    end
    if (best) then
	if (not router.ap or best.ssid ~= router.ap.ssid or best.bssid ~= router.ap.bssid or router.state == router.INIT) then
          mprint("-- Total APs: ", #arr,"Connecting to best",best.bssid)
	  router.ap={ssid=best.ssid,channel=best.channel,bssid=best.bssid}
	  router.state=router.JOINING
          wifi.sta.connect(best)
	else
          mprint("-- Total APs: ", #arr,"Already connected to best",best.bssid)
	end
    else
      mprint("-- Total APs: ", #arr,"No best match")
    end
  end
end

function router.scan()
  wifi.sta.scan({ hidden = 1 }, router.scan_results)
end

function router.timer_expired()
  mprint("timer expired",router.state,router.ssid,router.ap_ip,router.sta_ip)
  if (router.state == router.INIT or router.state == router.CONFIGURED) then
    router.scan()
  end
  if (router.state == router.JOINED) then
    router.errors=router.errors+1
    if (router.errors > 3) then
      router.state = router.INIT
    else
      router.send_info()
    end
  end
  router.timer:alarm(5000, tmr.ALARM_SINGLE, router.timer_expired)
end

wifi.sta.on("connected",router.sta_on)
wifi.sta.on("got_ip",router.sta_on)
wifi.ap.on("sta_connected",router.ap_on)
router.state=router.INIT
router.scan()
router.socket=net.createUDPSocket()
router.socket:listen(9999)
router.socket:on("receive", router.udp_on)
router.timer = tmr.create()
router.timer:alarm(5000, tmr.ALARM_SINGLE, router.timer_expired)

--socket:on("receive", function(s, data, port, ip)
--    mprint(string.format("received '%s' from %s:%d", data, ip, port))
--end)
