cmd_check_alert:
  supervisor:
    cron: '*/5'
    config:
      enabled: True
      limits:
        time: 300
        threads: 1
      defaults:
        timeout: 15
        severity: fatal
      checks:
        supervisor-status:
          cmd: systemctl is-active supervisor.service && ! supervisorctl status | grep 'FATAL'
          service: service
          resource: __hostname__:supervisor-status
