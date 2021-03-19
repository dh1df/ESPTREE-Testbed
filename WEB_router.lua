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
   send_buffered('sta IP ',router.sta_ip,'<br/>')
   send_buffered('ap IP ',router.ap_ip,'<br/>')
   send_buffered('gw ',router.gw,'<br/>')
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
        send_buffered(' ',k2,' ',v2,'<br/>')
      end
   end
end
