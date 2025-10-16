cmd_check_alert:
  mariadbd:
    cron: '*/4'
    config:
      enabled: True
      limits:
        time: 240
        threads: 5
      defaults:
        timeout: 15
        severity: fatal
      checks:
        mariadbd:
          cmd: systemctl is-active mariadb.service && ps ax | grep '/usr/sbin/mariadb[d]'
          service: service
          resource: __hostname__:mariadbd
