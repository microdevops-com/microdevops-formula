cmd_check_alert:
  mysql_master_status:
    cron: '*/5'
    config:
      enabled: True
      limits:
        time: 60
        threads: 1
      defaults:
        timeout: 15
        severity: critical
      checks:
        mysql_master_status:
          cmd: /opt/sysadmws/misc/mysql_master_status.sh
          service: mysql
          resource: __hostname__:mysql-master-status
          severity_per_retcode:
            2: critical
