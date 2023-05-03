cmd_check_alert:
  redis_memory:
    cron: '*/15'
    config:
      enabled: True
      limits:
        time: 60
        threads: 1
      defaults:
        timeout: 5
        severity_per_retcode:
          0: ok
          1: warning
          2: critical
      checks:
        check_used_memory_rss:
          cmd: /opt/sysadmws/misc/check_redis_memory.py --redis-password ${REDIS_PASSWORD}
          service: redis
          resource: __hostname__:redis-memory
