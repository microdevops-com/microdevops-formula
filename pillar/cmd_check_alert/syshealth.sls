cmd_check_alert:
  syshealth:
    cron: '*/10'
    config:
      enabled: True
      limits:
        time: 900
        threads: 5
      defaults:
        timeout: 15
        severity: fatal
      checks:
        has-oom-kills:
          cmd: '! dmesg -T | grep "Out of memory"'
          service: os
          resource: __hostname__:oom
        has-zombies:
          cmd: '! grep zombie /proc/*/status -q'
          service: os
          resource: __hostname__:zombie
