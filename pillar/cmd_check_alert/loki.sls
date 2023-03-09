cmd_check_alert:
  loki:
    cron: '*/15'
    install_sensu-plugins:
      - http # https://github.com/sensu-plugins/sensu-plugins-http/blob/master/bin/check-http.rb
    config:
      enabled: True
      limits:
        time: 600
        threads: 5
      defaults:
        timeout: 100
        severity: fatal
      checks:
        loki-read:
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-http.rb --dns-timeout 1.5 --read-timeout 30 --open-timeout 30  --timeout 30 --expiry 20 --query "ready" --url http://127.0.0.1:3100/ready
          resource: __hostname__:loki
          service: loki
