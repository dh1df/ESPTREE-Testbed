return function (info)
--        if (not authenticated()) then
--               return
--        end
   send_buffered(info.http_preamble)
   if (not router) then
      send_buffered('Router not active')
      return
   end
   send_buffered('Status ',router.state,'<br/>')
   send_buffered('Errors ',router.errors,'<br/>')
   send_buffered('SSID ',router.full_ssid,'<br/>')
   if (router.ap) then
      for k,v in pairs(router.ap) do
        send_buffered('ap ',k,' ',v,'<br/>')
      end
   end
   for k,v in pairs(router.ap_clients) do
      send_buffered('sta ',k,'<br/>')
   end
   for k,v in pairs(router.client_by_mac) do
      send_buffered('tree sta ',k,':<br/>')
      for k2,v2 in pairs(v) do
	if (k2 == 'ip') then
          send_buffered(' ip <a href="http://',v2,'/router">',v2,'</a><br/>')
        else
          send_buffered(' ',k2,' ',v2,'<br/>')
	end
      end
   end
   local iface={}
   for k,v in pairs(net) do
     if (k:sub(1,3) == 'IF_') then
       iface[v]=k:sub(4)
     end
   end
   if (router.sta_info) then
     send_buffered('0.0.0.0 0 ',router.sta_info.gw,' *WIFI_STA</br>')
     send_buffered(router.sta_info.ip,' ',router.sta_info.netmask,' ',router.sta_info.ip,' *WIFI_STA</br>')
   end
   send_buffered(router.ap_ip,' 24 ',router.ap_ip,' *WIFI_AP</br>')
   for i=0,net.route.getlen()-1 do
    local route=net.route.get(i)
    if (route and route.dest) then
      send_buffered(route.dest,' ',route.prefixlen,' ',route.nexthop,' ',iface[route.iface],'</br>')
    end
  end
end
