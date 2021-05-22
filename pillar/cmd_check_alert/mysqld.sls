cmd_check_alert:
  mysqld:
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
        mysqld:
          cmd: systemctl is-active mysql.service && ps ax | grep '/usr/sbin/mysql[d]'
          service: service
          resource: __hostname__:mysqld
