cmd_check_alert:
  postgresql-16:
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
        postgresql-16:
          cmd: systemctl is-active postgresql@16-main.service && ps ax | grep '/usr/lib/postgresql/16/bin/postgres'
          service: service
          resource: __hostname__:postgresql-16
