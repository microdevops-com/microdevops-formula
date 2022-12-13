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
        mysqld:
          cmd: systemctl is-active mysql.service && ps ax | grep '/usr/sbin/mysql[d]'
          service: service
          resource: __hostname__:mysqld
        xinetd:
          cmd: systemctl is-active xinetd.service && ps ax | grep '/usr/sbin/xinet[d]'
          service: service
          resource: __hostname__:xinetd
