# Per-connection TCP autotuning range, 16 MiB max, for high-RTT links.
# Triplet is "min default max" (bytes). min/default are left at kernel norms so a
# fresh socket starts small; the kernel autotunes up toward 16 MiB only when the
# bandwidth-delay product needs it (bulk transfer over a long path). Pairs with
# net-mem-16777216.sls, which raises the hard ceiling these values grow within.
sysctl:
  default:
    net.ipv4.tcp_rmem: 4096 131072 16777216
    net.ipv4.tcp_wmem: 4096 16384 16777216
