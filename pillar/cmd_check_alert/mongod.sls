cmd_check_alert:
  mongod:
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
        mongod:
          cmd: systemctl is-active mongod.service && ps ax | grep '/usr/bin/mongo[d]'
          service: service
          resource: __hostname__:mongod
