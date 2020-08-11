cmd_check_alert:
  checks:
      lsyncd:
        cmd: systemctl is-active lsyncd.service && ps ax | grep '/usr/bin/lsync[d]'
        service: service
        resource: __hostname__:lsyncd
