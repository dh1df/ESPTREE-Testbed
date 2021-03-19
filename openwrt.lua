require 'socket'
require 'luci.jsonc'
wifi={ap={},sta={}}
net={}
tmr={}
sockets={}
sjson={encode=luci.jsonc.stringify,decode=luci.jsonc.parse}

function net.createUDPSocket()
	ret = {
		listen=function(self,port)
		  print('listen',port)
		  self._socket:setsockname('*',port)
		end,
		send=function(self,port,ip,data)
		  self._socket:sendto(data,ip,port)
		end,
		on=function(self,event,func)
		  self._events[event]=func
		end,
		_receive=function(self)
		  data,ip,port=self._socket:receivefrom()
		  self._events.receive(self,data,port,ip)
		end,
		_socket=socket.udp(),
		_events={}
	}
	table.insert(sockets,ret)
	return ret
end

function tmr.create()
	return {
		alarm=function()
		end
	}
end

function wifi.mode()
end

function wifi.setps()
end

function wifi.start()
end

function wifi.stop()
end

function wifi.sta.on()
end

function wifi.sta.scan()
end

function wifi.sta.config()
end

function wifi.ap.on()
end

function wifi.ap.getmac()
  return 'none'
end

dofile 'router.lua'
router.topology={6,3,2,1,1,1,1,1}
router.state=router.CONFIGURED_FIXED
router.ssid='ESPTREE'
router.minip=0x0a0a0000
router.maxip=0x0a0af0ff

while true do
  fds={}
  fdsocket={}

  for i,socket in ipairs(sockets)
  do
	if (socket._events.receive)
	then
		table.insert(fds, socket._socket)
		fdsocket[socket._socket]=socket
	end
  end
  print(fds)
  -- posix.poll.poll(fds)
  rfds,wfds,msg=socket.select(fds, nil)
  for i,fd in ipairs(rfds)
  do
	fdsocket[fd]:_receive()
  end
end
