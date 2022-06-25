cmd_check_alert:
  pxc:
    cron: '*/2'
    config:
      enabled: True
      limits:
        time: 60
        threads: 5
      defaults:
        timeout: 15
        severity: fatal
      checks:
        pxc:
          cmd: /opt/sysadmws/misc/pxc_check.sh
          service: database
          resource: __hostname__:pxc
