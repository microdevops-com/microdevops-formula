# Testing Loki Setup

Wrong Loki setup can have issues.
We can ingest several GB of logs for test and check that data matches then.

## Create test logs

See: https://github.com/mingrammer/flog

Example `docker-compose.yaml`:

```
version: "3.8"
services:
  log-generator:
    image: mingrammer/flog
    command:
      - --format=json
      #- --number=1000000 # number of log lines to generate per second
      - --delay=0.05ms # delay between log lines
      - --output=/var/log/generated-10G.log.bak
      - --overwrite
      - --type=log
      #- --sleep=1
      - --bytes=10737418240
      #- --loop
    volumes:
      - /mnt/:/var/log/
```

## Testing script

It is recommended to run it several consecutive times.

```
#!/bin/bash

# Stop and reset promtail
salt-ssh web1.tst.example.com cmd.run "systemctl stop promtail.service; rm /opt/promtail/etc/positions.yaml"

# Clear loki data
salt-ssh -E "loki-(front1|front2|reader1|reader2|writer1|writer2).tst.example.com" cmd.run "systemctl stop loki; rm -rf /opt/loki"

# Clear loki cache in redis
salt-ssh redis1.tst.example.com cmd.run "redis-cli flushall"

# Stop and clean minio storage that loki uses
salt-ssh -E "loki-minio[1-8].tst.example.com" cmd.run "systemctl stop minio; rm -rf /opt/minio/data/*/.*; rm -rf /opt/minio/data/*/*;"

# Reinit minio
salt-ssh -E "loki-minio[1-8].tst.example.com" state.apply minio

# Recreate buckets in minio
salt-ssh loki-minio1.tst.example.com state.apply minio.buckets

# Bring loki up back
salt-ssh -E "loki-(front1|front2|reader1|reader2|writer1|writer2).tst.example.com" state.apply loki.systemd
sleep 60

# Ingest the test log file to loki with promtail
salt-ssh source1.tst.example.com cmd.run "systemctl start promtail.service"
sleep 360
```

## Compare the line count in the test log file and loki

```
export LOKI_ORG_ID=loki-cluster
export LOKI_ADDR=https://loki-gateway1.tst.example.com
logcli instant-query 'count_over_time({filename=~"/mnt/generated-.*"} [240h])'
```
