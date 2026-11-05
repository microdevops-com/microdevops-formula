# CVE-2026-98432 (IPv4 TCP request socket use-after-free, remote, unauthenticated, any
# listening TCP port; public exploit chain needs an MPTCP listener, which every Go >= 1.24
# daemon opens by default). Interim mitigation while no fixed kernel is running: ufw's
# /etc/ufw/before.init inserts a raw PREROUTING chain that drops inbound TCP carrying IP
# options (IHL > 5), before conntrack and DNAT, so host ports and NATed container ports
# are both covered. cve_probe reports the host as "mitigated" once it is active.
#
# Needs the xt_u32 match: present in stock Ubuntu/Debian/RHEL kernels. Inside an LXC/Incus
# guest it works only after the host loaded the module (apply to the host first). Guests
# with their own bridged public IP need this pillar themselves, the host rule does not see
# their traffic. If the match is unavailable the script warns and the firewall still loads.
#
# Remove later by setting the key to False (the chain is deleted on the next reload) and
# dropping the include once a fixed kernel runs; cve_probe shows "fixed" at that point.
ufw:
  cve_2026_98432_mitigation: True
