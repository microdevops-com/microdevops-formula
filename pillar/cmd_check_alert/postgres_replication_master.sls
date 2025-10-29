cmd_check_alert:
  postgresql_replica_master:
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
        postgresql_bytes_replica_lag:
          cmd: sudo -iu postgres psql -t -c 'SELECT pg_stat_replication.sent_lsn - pg_stat_replication.replay_lsn AS byte_lag FROM pg_stat_replication;' | grep -v -e '^$' | sed 's/ //g' | { read lag; echo $lag; if [ "${lag%.*}" -gt 10000000000 ]; then echo not ok; exit 1; else echo ok; exit 0; fi }
          resource: __hostname__:postgresql_bytes_replica_lag
          group: __hostname__
          service: postgresql
        postgresql_replica_state:
          cmd: sudo -iu postgres psql -t -c 'select state,sync_state from pg_stat_replication' |grep -ve '^$' | grep -q 'streaming | async'
          resource: __hostname__:postgresql_replica_state
          group: __hostname__
          service: postgresql
