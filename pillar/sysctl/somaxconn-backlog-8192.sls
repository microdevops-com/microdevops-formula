sysctl:
  default:
    net.core.somaxconn: 8192 # x2
    net.core.netdev_max_backlog: 8192 # x8
    net.ipv4.tcp_max_syn_backlog: 8192 # x2
