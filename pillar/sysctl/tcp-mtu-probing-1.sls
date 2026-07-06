# Enable Path MTU discovery probing.
# On some paths/tunnels the ICMP "fragmentation needed" messages are dropped, so
# oversized packets vanish silently (PMTU blackhole) -- large responses stall
# while small ones work. With probing on, TCP detects this and shrinks the MSS
# itself instead of hanging. Cheap insurance, especially behind VPN/tunnel hops.
sysctl:
  default:
    net.ipv4.tcp_mtu_probing: 1
