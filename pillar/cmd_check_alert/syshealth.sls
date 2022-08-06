cmd_check_alert:
  syshealth:
    cron: '*/10'
    install_sensu-plugins:
      - process-checks
    config:
      enabled: True
      limits:
        time: 900
        threads: 5
      defaults:
        timeout: 15
        severity: critical
      checks:
        has-oom-kills:
          cmd: :; ! dmesg -T | grep "Out of memory"
          service: os
          resource: __hostname__:oom
          severity_per_retcode:
            1: critical
        has-zombies:
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-process.rb -s Z -W 0 -C 0 -w 10 -c 15
          service: os
          resource: __hostname__:zombie
          severity_per_retcode:
            1: major
            2: critical
