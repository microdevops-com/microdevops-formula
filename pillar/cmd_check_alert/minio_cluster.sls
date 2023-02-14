cmd_check_alert:
  minio_cluster:
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
        node-liveness:
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-http.rb --dns-timeout 1.5 --read-timeout 30 --open-timeout 30  --timeout 30 --expiry 20 --url http://localhost:9000/minio/health/live
          resource: __hostname__:minio-node-liveness
          service: minio
        cluster-write-quorum:
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-http.rb --dns-timeout 1.5 --read-timeout 30 --open-timeout 30  --timeout 30 --expiry 20 --url http://localhost:9000/minio/health/cluster
          resource: __hostname__:minio-cluster-write-quorum
          service: minio
        cluster-read-quorum:
          cmd: /opt/sensu-plugins-ruby/embedded/bin/check-http.rb --dns-timeout 1.5 --read-timeout 30 --open-timeout 30  --timeout 30 --expiry 20 --url http://localhost:9000/minio/health/cluster/read
          resource: __hostname__:minio-cluster-read-quorum
          service: minio
