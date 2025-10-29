cmd_check_alert:
  psql_replica_slave:
    cron: '*'
    config:
      enabled: True
      limits:
        time: 600
        threads: 5
      defaults:
        timeout: 15
        severity: critical
      checks:
        psql_secs_replica_lag:
          cmd: sudo -iu postgres psql -t -c 'select now()-pg_last_xact_replay_timestamp() as replication_lag;' | grep -v -e '^$' | awk -F':' '{ print ($1 * 3600) + ($2 * 60) + $3 }' | { read lag; echo $lag; if [ "${lag%.*}" -gt 3600 ]; then echo not ok; exit 1; else echo ok; exit 0; fi }
          resource: __hostname__:psql_secs_replica_lag
          group: __hostname__
          service: psql
