cmd_check_alert:
  check_gitlab_backup:
    cron: '*'
    cron_disabled: True
    config:
      enabled: True
      limits:
        time: 3600
        threads: 1
      defaults:
        timeout: 3600
        severity: critical
      checks:
        check_gitlab_backup:
          cmd: /opt/microdevops/misc/check_gitlab_backup.py --dir /var/backups/gitlab_backups
          service: gitlab
          resource: __hostname__:gitlab-backup
