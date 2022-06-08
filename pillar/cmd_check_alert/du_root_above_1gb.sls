cmd_check_alert:
  du_root_above_1gb:
    cron: '*/15'
    config:
      enabled: True
      limits:
        time: 60
        threads: 5
      defaults:
        timeout: 15
        severity: critical
      checks:
        du_root_above_1gb:
          cmd: 'if [[ $(du -sb /root | cut -f1) -gt 1000000000 ]]; then false; else true; fi'
          service: disk
          resource: __hostname__:/root
