sysctl:
  /etc/sysctl.d/99-kubernetes.conf:
    net.ipv4.ip_forward: 1
    net.ipv4.tcp_congestion_control: bbr
    
    vm.overcommit_memory: 1
    kernel.panic: 10
    kernel.panic_on_oops: 1

    fs.file-max: 1000000
    fs.inotify.max_user_watches: 2099999999
    fs.inotify.max_user_instances: 2099999999
    fs.inotify.max_queued_events: 2099999999
