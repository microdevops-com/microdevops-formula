cmd_check_alert:
  lsyncd:
    cron: '*/15'
    config:
      enabled: True
      limits:
        time: 900
        threads: 5
      defaults:
        timeout: 15
        severity: fatal
      checks:
        lsyncd:
          cmd: systemctl is-active lsyncd.service && ps ax | grep '/usr/bin/lsync[d]'
          service: service
          resource: __hostname__:lsyncd
