# BBR congestion control for long-RTT nodes (cross-continent proxy/VPN egress).
# CUBIC (the default) reads any packet loss as congestion and halves the rate;
# on long paths sporadic loss is normal, so it throttles throughput to the floor.
# BBR instead measures the path's real bandwidth and RTT and paces to that, so it
# keeps the pipe full and is not derailed by non-congestive loss.
#
# REQUIRES the tcp_bbr kernel module. It is a module (not built-in) on stock
# Ubuntu/Debian kernels, so it must be loaded before this value can apply --
# setting tcp_congestion_control=bbr silently no-ops if the module is absent.
# Load and persist it (outside sysctl, e.g. a kernel-module state or by hand):
#   modprobe tcp_bbr
#   echo tcp_bbr > /etc/modules-load.d/bbr.conf
# Verify: `sysctl net.ipv4.tcp_congestion_control` must return `bbr`.
sysctl:
  default:
    net.ipv4.tcp_congestion_control: bbr
    # fq is the pacing-friendly qdisc BBR prefers. Optional: on kernels >= 4.13
    # BBR self-paces even with fq_codel. This only takes effect on new qdiscs,
    # i.e. after an interface reset or reboot -- it does not disrupt live links.
    net.core.default_qdisc: fq
