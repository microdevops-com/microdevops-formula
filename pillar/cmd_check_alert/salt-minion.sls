cmd_check_alert:
  salt-minion:
    cron: '*/10'
    config:
      enabled: True
      limits:
        time: 600
        threads: 5
      defaults:
        timeout: 15
        severity: fatal
      checks:
        salt-minion:
          cmd: systemctl is-active salt-minion.service && ps ax | grep '/usr/bin/salt-minio[n]'
          service: service
          resource: __hostname__:salt-minion
