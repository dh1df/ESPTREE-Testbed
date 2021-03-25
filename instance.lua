sjson=require 'json'

wifi={STATIONAP=1,HT20=1,OPEN=1,ap={},sta={}}
net={route={},dns={getdnsserver=function(v) return "dummy" end}}
tmr={ALARM_SINGLE=1,ALARM_SEMI=2,ALARM_AUTO=3}

function wifi.mode(v)
  -- print("wifi.mode",v,wifi)
end
function wifi.setps(v)
end
function wifi.start(v)
  -- print("wifi.start",wifi,v)
end
function wifi.stop()
end
function wifi.sta.connect(v)
  -- print("wifi.sta.connect",wifi,wifi.sta,v)
end

function wifi.sta.config(v) 
  if (v.ssid == '') then
    return
  end
  if (current.sta.active_bssid) then
    local connection=current.sta.connection[current.sta.active_bssid]
    connection.active=nil
    connection.ap_instance.ap.connection[current.sta.mac].active=nil
  end
  local connection=current.sta.connection[v.bssid]
  current.sta.active_bssid=v.bssid
  local ap_instance=connection.ap_instance
  local ap=ap_instance.ap
  local sta_instance=current
  local sta=sta_instance.sta
  connection.active=1
  ap.connection[current.sta.mac].active=1
  -- print("wifi.sta.connect",wifi,wifi.sta,wifi.sta._internal.connection[v.bssid],wifi.sta._internal.event.got_ip)
  ap_instance:ap_on("sta_connected",{mac=sta.mac,id=1})
  sta_instance:sta_on("connected",{ssid=ap.ssid,bssid=ap.mac,channel=ap.channel,auth=wifi.OPEN})
  local dhcp=ap_instance:run_dhcp(sta_instance.sta.mac)
  for k,v in pairs(dhcp) do sta[k] = v end
  sta_instance:sta_on("got_ip",dhcp)
end

function wifi.sta.scan(p,cb)
  -- print("wifi.sta.scan",wifi,wifi.sta,p,cb)
  current.sta.scan.p=p
  current.sta.scan.cb=cb
  tmr.create():alarm(30, tmr.ALARM_SINGLE, function (t) current:process_scans() end)
end

function wifi.sta:_on(event, info)
  cb=self._internal.event[event]
  if (cb) then
    -- print("wifi.sta.on","restore",self._internal.instance)
    self._internal.instance:restore()
    cb(event, info)
  end
end

function wifi.sta.on(event, callback)
  current.sta.event[event]=callback
end

function wifi.ap.config(v)
  -- print("wifi.ap.config",wifi,v,v.ssid,v.channel)
  for _,k in ipairs{"ssid","channel"}
  do
    current.ap[k]=v[k]
  end
end

function wifi.ap.getmac()
  return current.ap.mac
end

function wifi.ap.setip(v)
  -- print("wifi.ap.setip",v,v.ip,v.netmask)
  if (v.ip and current.ap.ip and v.ip ~= current.ap.ip) then
    current.dhcp={}
    current.dhcp_offset=0
  end
  for _,k in ipairs{"ip","netmask","gateway","dns"}
  do
    -- print("wifi.ap.setip",k,v[k])
    current.ap[k]=v[k]
  end
end



function wifi.ap.on(event, callback)
  current.ap.event[event]=callback
end

function net.route.add(v)
  -- print("net.route.add",net,net.route,v)
end
function net.route.getlen()
  -- print("net.route.getlen",net,net.route)
  return 2
end
function net.route.get(v)
  -- print("net.route.get",net,net.route,v)
  return {dest=nil}
end

function net.createUDPSocket()
  return {
    listen=function(self, port)
      self._listen=port
      current.sockets[port]=self
    end,
    on=function(self, event, func)
      self._events[event]=func
    end,
    send=function(self, port, ip, data)
      current:send_packet{srcport=self._listen, dstport=port, dstip=ip, data=data}
    end,
    _events={}
  }
end

function tmr.create()
  return {
    register=function(self,interval,mode,func)
      self._interval=interval
      self._func=func
      -- print("tmr register",self,interval,mode,func)
    end,
    start=function(self)
      -- print("tmr start",self,posix.clock_gettime(0))
      self.target={posix.clock_gettime(0)}
      self.target[2]=self.target[2]+(self._interval%1000)*1000000
      self.target[1]=self.target[1]+math.floor(self._interval/1000)+math.floor(self.target[2]/100000000000)
      self.target[2]=self.target[2]%1000000000
      self.instance=current
      -- print("tmr.create",self,instance)
      table.insert(current.timers, self)
    end,
    alarm=function(self,interval,mode,func)
      self:register(interval,mode,func)
      self:start()
    end,
    _run=function(self,instance)
      instance:restore()
      self._func(self)
    end
  }
end

instance={}

function instance.create()
   local linstance={connections={},dhcp={},dhcp_offset=0,sockets={},timers={},ap={connection={},event={}},sta={connection={},event={},scan={}}}
   for k,v in pairs(instance) do linstance[k]=v end
   linstance.ap.mac=string.format("%02x:%02x:%02x:%02x:%02x:%02x",math.random(0,255),math.random(0,255),math.random(0,255),math.random(0,255),math.random(0,255),math.random(0,255))
   linstance.sta.mac=string.format("%02x:%02x:%02x:%02x:%02x:%02x",math.random(0,255),math.random(0,255),math.random(0,255),math.random(0,255),math.random(0,255),math.random(0,255))
   current=linstance
   dofile "router.lua"
   router.start()
   linstance:save()
   return linstance
end

function instance:ap_on(event, info)
  cb=self.ap.event[event]
  if (cb) then
    self:restore()
    cb(event, info)
  end
end

function instance:run_dhcp(mac)
  -- print("instance.run_dhcp",mac,self.ap.ip)
  local dhcp=self.dhcp[mac]
  if (not dhcp) then
    local ip=self.ap.ip
    local bytes={}
    for byte in string.gmatch(ip, "[^.]+") do
      table.insert(bytes, tonumber(byte))
    end
    bytes[4]=bytes[4]+1+self.dhcp_offset
    ip=table.concat(bytes,'.')
    self.dhcp_offset=self.dhcp_offset+1
    dhcp={ip=ip,netmask=self.ap.netmask,gw=self.ap.ip};
    self.dhcp[mac]=dhcp
  end
  return dhcp
end

function instance:process_scans()
   -- print("process_scans",self)
   self:restore()
   local aps={}
   for mac,connection in pairs(self.sta.connection) do
       -- print("process_scans",mac,connection)
       local ap=connection.ap
       if (ap.ssid) then
          table.insert(aps,{ssid=ap.ssid,channel=ap.channel,bssid=ap.mac,rssi=connection.rssi,auth=wifi.OPEN,bandwidth=wifi.HT20})
       end
   end
   self.sta.scan.cb(nil,aps)
end

function instance:restore()
  local ret=current
  router=self.router
  current=self
  return ret
end

function instance:save()
  self.router=router
end

function instance:get_connection(packet)
  for mac,connection in pairs(self.sta.connection) do
    if (connection.active and connection.ap.ip == packet.dstip) then
      -- print("found",ip,"on",connection.ap_instance)
      packet.srcip=self.sta.ip
      packet.dstinstance=connection.ap_instance
      packet.iface=self.sta
      return true
    end
  end
  for mac,connection in pairs(self.ap.connection) do
    if (connection.active and connection.sta.ip == packet.dstip) then
      packet.srcip=self.ap.ip
      packet.dstinstance=connection.sta_instance
      packet.iface=self.ap
      return true
    end
  end
  print("no destination for ",packet.dstip)
  return false
end

function instance:send_packet(packet)
  if (self:get_connection(packet)) then
    local save=packet.dstinstance:restore()
    -- print("send_packet",self,packet.dstip,packet.dstport,packet.dstinstance,data)
    tmr.create():alarm(30, tmr.ALARM_SINGLE, function (t) current:receive_packet(packet) end)
    save:restore()
  end
end

function instance:receive_packet(packet)
  -- print("receive_packet",self,packet.srcport,packet.srcip, packet.dstport, packet.dstip, packet.data)
  local socket=self.sockets[packet.dstport]
  -- print("socket",socket)
  socket._events['receive'](socket,packet.data,packet.srcport,packet.srcip)
end

function instance:sta_on(event, info)
  cb=self.sta.event[event]
  if (cb) then
    self:restore()
    cb(event, info)
  end
end

function instance:dump()
   print("instance",self,"router",self.router)
   print("ap",self.ap.mac,"sta",self.sta..mac)
end

function instance:connect(other,rssi)
   local ap=self.ap
   local sta=self.sta
   local oap=other.ap
   local osta=other.sta
   local connection={ap=ap,ap_instance=self,sta=osta,sta_instance=other,rssi=rssi}
   ap.connection[osta.mac]=connection
   osta.connection[ap.mac]=connection
   connection={ap_instance=other,ap=oap,sta=sta,sta_instance=self,rssi=rssi}
   oap.connection[sta.mac]=connection
   sta.connection[oap.mac]=connection
   -- print("connect",osta._internal.mac,ap._internal.mac)
   -- print("connect",sta._internal.mac,oap._internal.mac)
end

function t_delta(t1,t2)
	-- print(t1,t2)
        s=t1[1]-t2[1]
	ns=t1[2]-t2[2]
	if (ns < 0) then
	   s=s-1
	   ns=ns+1000000000
	end
	return {s,ns}
end

function t_zero_or_negative(t)
        return (t[1] < 0 or (t[1] == 0 and t[2] == 0))
end

function instance.get_dot()
  local ret='digraph graphname\n{\n'
  for i,instance in ipairs(instances) do
    local stastr
    if (instance.ap.ssid) then
      stastr='"'..instance.ap.ssid..'\\n'..instance.ap.mac..'"'
    else
      stastr='"'..instance.ap.mac..'"'
    end
    local found=false
    for i,connection in pairs(instance.sta.connection) do
      local ap=connection.ap_instance.ap
      if (ap.ssid) then
        local apstr='"'..ap.ssid..'\\n'..ap.mac..'"'
        local attrs='label=' .. connection.rssi
        if (connection.active) then
          attrs=attrs..",color=green"
        end
        ret=ret .. stastr .. " -> " .. apstr .. "[" .. attrs .. "]\n"
        found=true
      end
    end
    if (not found) then
        ret=ret .. stastr .. "\n"
    end
  end
  ret=ret .. '}\n'
  return ret
end

last_dot=''
dotcount=0

function instance.write_dot()
  local dot=instance.get_dot()
  if (dot ~= last_dot) then
    last_dot=dot
    local filename="nodes"..dotcount..".dot"
    local file = io.open (filename,"w")
    file:write(dot)
    file:close()
    os.execute("dot -T png "..filename.." > current.png.tmp ; mv current.png.tmp current.png")
    dotcount=dotcount+1
  end
end
	
function instance.process_all_timers(instances)
  instance.write_dot()
  local now={posix.clock_gettime(0)}
  local min
  -- print('now',now)
  for i,instance in ipairs(instances) do
     local next
     for i=#instance.timers,1,-1 do
	local tmr=instance.timers[i]
	-- print("instance",instance,"tmr",tmr)
        delta=t_delta(tmr.target, now)
        if (t_zero_or_negative(delta)) then
	   tmr:_run(instance)
           -- print("tmr",i,tmr,#instance.timers)
	   table.remove(instance.timers,i)
           -- print("tmr removed",i,tmr,#instance.timers)
	else
          if (min) then
  	    mind=t_delta(delta,min)
  	    if (t_zero_or_negative(mind)) then
              min=delta
  	    end
          else
            min=delta
          end
	end
     end
  end
  if (min) then
    -- print("min",min[1],min[2])
    local timeout=min[1]*1000+min[2]/1000000;
    -- print("timeout",timeout)
    posix.poll({},math.floor(timeout))
    return true
  end
  return false
end

-- instance:save()
-- instance:dump()

-- return instance
