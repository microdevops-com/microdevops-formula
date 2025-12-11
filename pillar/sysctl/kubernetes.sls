sysctl:
  /etc/sysctl.d/99-kubernetes.conf:
    ########################################
    # Kubernetes core networking
    ########################################
    net.ipv4.ip_forward: 1
    net.ipv6.conf.all.forwarding: 1
    
    ########################################
    # CNI compatibility (Calico / Cilium / Flannel)
    ########################################
    # Reverse path filter must be disabled for overlay routing
    net.ipv4.conf.all.rp_filter: 0
    net.ipv4.conf.default.rp_filter: 0
    
    # Required so that iptables can see bridged traffic
    net.bridge.bridge-nf-call-iptables: 1
    net.bridge.bridge-nf-call-ip6tables: 1
    
    ########################################
    # Neighbor cache tuning (prevent ARP/ND overflow)
    ########################################
    net.ipv4.neigh.default.gc_thresh1: 128
    net.ipv4.neigh.default.gc_thresh2: 512
    net.ipv4.neigh.default.gc_thresh3: 1024
    
    net.ipv6.neigh.default.gc_thresh1: 128
    net.ipv6.neigh.default.gc_thresh2: 512
    net.ipv6.neigh.default.gc_thresh3: 1024
    
    ########################################
    # Conntrack table size (important for kube-proxy)
    ########################################
    net.netfilter.nf_conntrack_max: 1048576
    net.netfilter.nf_conntrack_buckets: 262144
    
    ########################################
    # TCP / socket backlog tuning
    ########################################
    net.core.somaxconn: 1024
    net.core.netdev_max_backlog: 16384
    net.ipv4.tcp_max_syn_backlog: 8192
    
    ########################################
    # Etcd / API Server / containerd socket buffers
    ########################################
    net.ipv4.tcp_rmem: 4096 87380 6291456
    net.ipv4.tcp_wmem: 4096 65536 6291456
    net.core.rmem_max: 134217728
    net.core.wmem_max: 134217728
    
    ########################################
    # Inotify (reasonable safe values)
    ########################################
    fs.inotify.max_user_watches: 524288
    fs.inotify.max_user_instances: 1024
    fs.inotify.max_queued_events: 32768
    
    ########################################
    # File descriptors (global kernel limit)
    ########################################
    fs.file-max: 1000000
    
    ########################################
    # Pipe limits (fix EMFILE pipe(2) issue in Fluentd)
    ########################################
    fs.pipe-user-pages-soft: 262144
    fs.pipe-user-pages-hard: 262144
    
    ########################################
    # Memory overcommit (safe for container runtimes)
    ########################################
    vm.overcommit_memory: 1
    
    ########################################
    # Kernel crash behaviour (recommended for Kubernetes)
    ########################################
    kernel.panic: 10
    kernel.panic_on_oops: 1
    
    ########################################
    # Congestion control
    ########################################
    net.ipv4.tcp_congestion_control: bbr
