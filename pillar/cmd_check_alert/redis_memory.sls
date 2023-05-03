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
          cmd: |
            /opt/microdevops/misc/check_redis_memory.py --total-memory $(cat /etc/redis/redis.conf | grep "^maxmemory " | awk '{print $2}' | sed -e 's/Gb/000/') --redis-password $(cat /etc/redis/redis.conf | grep "^requirepass " | awk '{print $2}')
          service: redis
          resource: __hostname__:redis-memory
