cmd_check_alert:
  salt-master:
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
        salt-master:
          cmd: systemctl is-active salt-master.service && ps ax | grep '/usr/bin/salt-maste[r]'
          service: service
          resource: __hostname__:salt-master
