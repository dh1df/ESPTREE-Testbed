router={INIT=0,JOINING=1,JOINED=2,CONFIGURED=3,ROOT=4,LEAF=5,MODE_80211B=1,MODE_80211G=2,MODE_80211N=3,MODE_80211BGN=4,state=0,client_by_ssid={},client_by_mac={},errors=0,prefix='ESPTREE',change_counter=0,ap_clients={},routed={}}
router.speeds={
  [router.MODE_80211B]={
    [-98]=1,
    [-95]=2,
    [-89]=5.5,
    [-86]=11
  },
  [router.MODE_80211G]={
    [-93]=6,
    [-92]=9,
    [-91]=12,
    [-89]=18,
    [-85]=24,
    [-82]=36,
    [-78]=48,
    [-76]=54
  },
  [router.MODE_80211N]={
    [-93]=6.5,
    [-90]=13,
    [-87]=19.5,
    [-84]=26,
    [-81]=39,
    [-76]=52,
    [-75]=58.5,
    [-72]=65
  },
  [router.MODE_80211BGN]={
    [-98]=1,
    [-95]=2,
    [-93]=6.5,
    [-91]=12,
    [-90]=13,
    [-89]=18,
    [-87]=19.5,
    [-85]=24,
    [-84]=26,
    [-82]=36,
    [-81]=39,
    [-78]=48,
    [-76]=52,
    [-75]=58.5,
    [-72]=65
  }
}

function mprint(v,...)
  if (router.verbose) then
    if (v > router.verbose) then
      return
    end
  else
    if (verbose and v > verbose) then
      return
    end
  end
  if (wifi and wifi.ap and wifi.ap.getmac) then
    print(wifi.ap.getmac(),...)
  else
    print(...)
  end
end

function router.ap_on(event, info)
  mprint(1,"router.ap_on",event)
  if (event == 'sta_connected') then
     if (time) then
         router.ap_clients[info.mac],_=time.get();
     end
  end
  if (event == 'disconnected') then
     router.ap_clients[info.mac]=nil;
  end
end

-- https://stackoverflow.com/questions/8200228/how-can-i-convert-an-ip-address-into-an-integer-with-lua/8200301
--
function ip2dec(ip) local i, dec = 3, 0; for d in string.gmatch(ip, "%d+") do dec = dec + 2 ^ (8 * i) * d; i = i - 1 end; return dec end

function dec2ip(decip) local divisor, quotient, ip; for i = 3, 0, -1 do divisor = 2 ^ (i * 8); quotient, decip = math.floor(decip / divisor), decip % divisor; if nil == ip then ip = quotient else ip = ip .. "." .. quotient end end return ip end


function router.send_info()
  mprint(1,"sending ping to ",router.sta_info.gw)
  router.socket:send(9999,router.sta_info.gw,sjson.encode({command="ping",mac=wifi.ap.getmac(),ssid=router.ssid}))
end

function router.get_client_data_by_id(data)
  local iplen=(router.maxip-router.minip+1-256)/data.maxclients
  local minip=router.minip+256+(data.idx-1)*iplen
  local maxip=minip+iplen-1
  if (time) then
      data.last,_=time.get()
  end
  -- print("iplen",iplen,dec2ip(router.maxip),dec2ip(router.minip),dec2ip(minip),dec2ip(maxip))
  return{idx=data.idx,ssid=data.ssid,minip=dec2ip(minip),maxip=dec2ip(maxip)}
end

function router.ssid_depth(ssid)
  if (ssid:sub(0,router.prefix:len()) == router.prefix) then
    return ssid:len()-router.prefix:len()
  end
  return -1
end

function router.ssid_speed(ssid)
  local p=ssid:find('#')
  if (p) then
    return ssid:sub(p+1)/100
  end
  return 65
end

function router.ssid_client(i)
  return router.ssid..i
end

function router.ssid_extension()
  ext=math.floor(router.preference(router.ap)*100)
  return '#'..ext
end

function router.speed(mode,rssi)
  local ret=0
  for i,v in pairs(router.speeds[mode]) do
    if (i < rssi and ret < v) then
      ret=v
    end
  end
  return ret
end

function router.combined_speed(speed1, speed2)
  if (speed1 == 0 or speed2 == 0) then
    return 0
  end
  return 1/(1/speed1+1/speed2)
end

function router.preference(ap)
   local speed2=router.speed(router.MODE_80211BGN,ap.rssi)
   local speed1=router.ssid_speed(ap.ssid)
   local factor=1
   if (router.ap and ap.bssid == router.ap.bssid) then
     factor=2
   end
   ret=router.combined_speed(speed1,speed2)
   return ret,factor
end

function router.get_client_data(request,ip)
  local level=router.ssid_depth(router.ssid)
  local maxclients=router.topology[level+1]
  if (router.client_by_mac[request.mac]) then
    return router.get_client_data_by_id(router.client_by_mac[request.mac])
  end
  for i=1,maxclients do
    local ssid=router.ssid_client(i)
    if (not router.client_by_ssid[ssid]) then
      router.client_by_ssid[ssid]=request.mac
      router.client_by_mac[request.mac]={ssid=ssid,idx=i,maxclients=maxclients,ip=ip}
      return router.get_client_data_by_id(router.client_by_mac[request.mac])
    end
  end
  mprint(1,"maxclients",maxclients,"reached",request.mac)
  return nil
end

function router.update_route(func,route)
        local div=2
        local mask=32
        local rem
	local first=route.first
	local last=route.last
        while (first < last) do
                rem=first%div
                if (rem ~= 0) then
			func{dest=dec2ip(first),prefixlen=mask,nexthop=route.nexthop,iface=route.iface}
                        first=first+div-rem
                end
                rem=last%div
                if (rem ~= div-1) then
			func{dest=dec2ip(last-rem),prefixlen=mask,nexthop=route.nexthop,iface=route.iface}
                        last=last-div+rem+1
                end
                div=div*2
                mask=mask-1
        end
end

function router.udp_on(s, data, port, ip)
  -- mprint(1,"router.udp_on",data,port,ip)
  local request=sjson.decode(data)
  mprint(1,"got",request.command,"from",ip)
  if (request.command == 'ping') then
    -- mprint(1,"ping",request.mac, ip, port)
    if (router.topology) then
      local data=router.get_client_data(request,ip)
      local oldip=router.routed[data.idx]
      if (oldip ~= ip) then
	 local route={first=ip2dec(data.minip),last=ip2dec(data.maxip),iface=net.IF_WIFI_AP}
	 if (oldip) then
           route.nexthop=oldip
	   router.update_route(net.route.delete,route)
         end
	 route.nexthop=ip
	 router.update_route(net.route.add,route)
	 router.routed[data.idx]=ip
      end
      data.command='pong'
      data.topology=router.topology
      reply=sjson.encode(data)
      mprint(1,"sending pong to ",router.ssid,ip,reply)
      router.socket:send(port,ip,reply)
    end
  end
  if (request.command == 'pong' and (router.state == router.JOINED or router.state == router.CONFIGURED)) then
    -- mprint(1,"pong", ip, port, request.topology[1])
    router.errors=0
    local update=false
    if (not router.topology or table.concat(router.topology,',') ~= table.concat(request.topology,',')) then
      mprint(1,"new topology",table.concat(request.topology,','));
      router.topology=request.topology
      update=true
    end
    if (request.ssid ~= router.ssid) then
      mprint(1,"new ssid",request.ssid);
      router.ssid=request.ssid
      router.client_by_ssid={}
      router.client_by_mac={}
      update=true
    end
    if (request.gen ~= router.gen) then
      mprint(1,"new gen",router.gen);
      router.gen=request.gen
      update=true
    end
    mprint(1,"ip range",request.minip,"-",request.maxip)
    if (update) then
      router.full_ssid=request.ssid .. router.ssid_extension(router.ap)
      mprint(1,'configuring ssid',router.full_ssid)
      wifi.ap.config{ssid=router.full_ssid,channel=router.ap.channel,pwd=router.password}
      router.minip=ip2dec(request.minip)
      router.maxip=ip2dec(request.maxip)
      local ip=dec2ip(router.minip+1)
      wifi.ap.setip{ip=ip,netmask='255.255.255.0',gateway=ip,dns=net.dns.getdnsserver(0)}
      router.ap_ip=ip
      router.state=router.CONFIGURED
    end
  end
end

function router.sta_on(event, info)
  mprint(1,"router.sta_on",event)
  if (event == 'got_ip' and router.ap) then
    mprint(1,"router.sta_on",event,info.ip,info.netmask,info.gw)
    router.sta_info=info
    router.errors=0
    if (router.state ~= router.LEAF) then
      router.state=router.JOINED
      router.send_info()
    end
  end
  if (event == 'disconnected') then
    if (router.state ~= router.LEAF) then
      router.state = router.INIT
    end
    router.init()
  end
end

function router.check_best(best)
  if (best == nil) then
    return false,'No best match'
  end
  if (router.ap and best.ssid == router.ap.ssid and best.bssid == router.ap.bssid and router.state ~= router.INIT) then
    router.change_counter=0
    return false,'Already connectet to best '..best.ssid
  end
  router.change_counter=router.change_counter+1
  if (router.ap and router.change_counter < 3) then
    return false,'Best is '..best.ssid..' but switch not yet possible'
  end
  return true,'Connecting to best '..best.ssid
end

function router.scan_results(err,arr)
  if err then
    mprint (1,"Scan failed:", err)
  else
    local best_pref=0
    local best
    local l=router.prefix:len()
    mprint(1,string.format("%-26s","SSID"),"Channel BSSID              RSSI Auth Bandwidth Pref")
    for i,ap in ipairs(arr) do
      pref,fac=router.preference(ap)
      mprint(1,string.format("%-32s",ap.ssid),ap.channel,ap.bssid,ap.rssi,ap.auth,ap.bandwidth,pref,fac)
      pref=pref*fac
      if (pref > best_pref and ap.ssid:sub(1,l) == router.prefix) and ap.ssid:sub(l+1,l+1) ~= '-' then
         best=ap
	 best_pref=pref
      end
    end
    local switch,message=router.check_best(best)
    mprint(1,"-- Total APs: ", #arr,message)
    if (switch) then 
      router.ap={}
      best.pwd=router.password
      for k,v in pairs(best) do router.ap[k]=v end
        router.state=router.JOINING
      wifi.sta.config(best)
      wifi.sta.connect()
    end
  end
end

function router.scan()
  local cfg={}
  if (router.ap) then
     mprint(1,'Scanning on channel ',router.ap.channel)
     cfg.channel=router.ap.channel
  else
     mprint(1,'Scanning on all channels')
  end
  pcall(wifi.sta.scan, cfg, router.scan_results)
end

function router.timer_expired()
  local interval=5000
  local sta_ip
  if (router.sta_info) then
    sta_ip=router.sta_info.ip
  end
  mprint(1,"timer expired",router.state,router.errors,router.ssid,router.ap_ip,sta_ip)
  if (router.state == router.INIT) then
    router.scan()
  end
  if (router.state == router.JOINED or router.state == router.CONFIGURED) then
    router.errors=router.errors+1
    if (router.errors > 3) then
      mprint(1,router.errors,' errors during state',router.state,'going back to router.INIT')
      router.state = router.INIT
      router.init()
    else
      router.send_info()
    end
  end
  if (router.state == router.CONFIGURED) then
    router.scan()
    interval=60000
  end
  router.timer:alarm(interval, tmr.ALARM_SINGLE, router.timer_expired)
end

function router.init()
  router.sta_info=nil
  router.ap=nil
  if (router.state == router.INIT) then
    wifi.stop()
    wifi.mode(wifi.STATIONAP)
    wifi.ap.on("sta_connected",router.ap_on)
    wifi.ap.on("sta_disconnected",router.ap_on)
    wifi.ap.config{ssid=router.prefix..'-Unconnected',channel=9,pwd=router.password}
    wifi.ap.setip{ip='192.168.4.1',netmask='255.255.255.0',gateway='192.168.4.1',dns='192.168.4.1'}
    wifi.setps(wifi.PS_NONE)
    router.topology=nil
    router.ssid=nil
    router.gen=nil
  end
  if (router.state == router.LEAF) then
    wifi.stop()
    wifi.mode(wifi.STATION)
  end
  if (router.state == router.INIT or router.state == router.LEAF) then
    wifi.sta.config{ssid='',auto=false}
    wifi.sta.on("connected",router.sta_on)
    wifi.sta.on("got_ip",router.sta_on)
    wifi.sta.on("disconnected",router.sta_on)
    wifi.start()
    router.scan()
  end
end

function router.start()
  router.init()
  if (router.state ~= router.LEAF) then
    router.socket=net.createUDPSocket()
    router.socket:listen(9999)
    router.socket:on("receive", router.udp_on)
  end
  router.timer = tmr.create()
  router.timer:alarm(5000, tmr.ALARM_SINGLE, router.timer_expired)
  router.start = nil
end
