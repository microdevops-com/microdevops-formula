cmd_check_alert:
  redis_rejected_connections:
    cron: '*/10'
    config:
      enabled: True
      limits:
        time: 60
        threads: 5
      defaults:
        timeout: 5
        severity: critical
      checks:
        rejected_connections_greater_than_0:
          cmd: '/opt/sysadmws/misc/check_redis_rejected_connections.sh'
          service: redis
          resource: rejected_connections
