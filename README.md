# ESPTREE-Testbed

ESPTREE is a minimalistic tree based routing protocol for ESP32 devices, intended for use with the Freifunk-ESP32-OpenMPPT solar
controllers. It is in some ways unconventional but offers IPv4 autoconfiguration, low CPU and bandwidth overhead. We are aiming at
energy autonomous least-cost wireless networks, providing IPv4 services like Internet access to end user devices, environmental
sensors and so on.

You can also use a OpenWRT-based WiFi device as a root node. 

The difference between ESPTREE and ESPMESH by Espressif is that we are aiming for the best networking performance that can be
achieved with an ESP32. We are using typical IPv4-based routing, IP-forwarding **without** Network Address Translation (NAT).
This is unlike ESPMESH, which encapsulates payload traffic.

ESP32 devices don't support multipoint-to-multipoint WiFi modes (ad-hoc or 802.11s), only software-accesspoint, station, 
software-accesspoint+station and monitor mode. 

Sending and receiving raw WiFi packages is possible, too, but we haven't explored running mesh networks using raw packages so far.
This would allow real multipoint-to-multipoint mesh topologies, at the cost of throughput and processing overhead. It could still be
interesting to implement this, though.

Hence, we are limited to setting up tree-like wireless networks with ESP32, unless we go down the road of the forementioned
RAW mode. But that would/will be a different endeavor.

