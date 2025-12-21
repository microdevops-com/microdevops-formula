cmd_check_alert:
  docker_no_unhealthy:
    cron: '*/20'
    config:
      enabled: True
      limits:
        time: 20
        threads: 1
      defaults:
        timeout: 10
        severity: critical
      checks:
        docker_no_unhealthy:
          cmd: :; ! docker ps | grep "(.*unhealthy.*)"
          service: docker
          resource: __hostname__:docker-no-unhealthy
