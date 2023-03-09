cmd_check_alert:
  docker-alive:
    cron: '*/10'
    config:
      enabled: True
      limits:
        time: 600
        threads: 1
      defaults:
        timeout: 120
        severity: fatal
      checks:
        salt-minion:
          cmd: docker run --rm alpine true
          service: service
          resource: __hostname__:docker
