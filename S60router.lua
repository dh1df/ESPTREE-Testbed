function rp()
	dofile('router.lua')
	router.prefix='ESPTREE'
	router.password='secret123'
	router.start()
	if (sta_hostname ~= nil and sta_hostname ~= '') then
		wifi.sta.sethostname(sta_hostname)
	end
end
function r()
	rp()
	autoreboot_disabled = 0
	nextreboot=5
end
