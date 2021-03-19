local cmds_route={}
local subcmds_route={}

function cmds_route.route(ctx,subcmd,...)
  return shell.cmd2(ctx,{subcmds_route},subcmd,...)
end

function subcmds_route.show(ctx,dest,via,dev)
  local iface={}
  for k,v in pairs(net) do
     if (k:sub(1,3) == 'IF_') then
       iface[v]=k:sub(4)
     end
  end
  for i=0,net.route.getlen()-1 do
    local route=net.route.get(i)
    if (route and route.dest) then
      ctx.stdout:print(route.dest,route.prefixlen,route.nexthop,iface[route.iface])
    end
  end
  return 0
end

function route_add_del(ctx,func,dest,prefixlen,nexthop,dev)
  local iface=net['IF_'..dev]
  if (not iface) then
     return -1
  end
  local route={dest=dest,prefixlen=prefixlen,nexthop=nexthop,iface=iface}
  func(route)
  return 0
end
function subcmds_route.add(ctx,...)
  return route_add_del(ctx,net.route.add,...)
end

function subcmds_route.delete(ctx,...)
  return route_add_del(ctx,net.route.delete,...)
end

return cmds_route
