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

salt-ssh -E "loki-minio(1|2|3|4|5|6|7|8).tst.example.com" cmd.run "echo 'set server minio-data/loki-minio1 state ready' | socat stdio /run/haproxy/admin.sock; echo 'set server minio-data/loki-minio2 state ready' | socat stdio /run/haproxy/admin.sock; echo 'set server minio-data/loki-minio3 state ready' | socat stdio /run/haproxy/admin.sock; echo 'set server minio-data/loki-minio4 state ready' | socat stdio /run/haproxy/admin.sock"
salt-ssh web1.tst.example.com cmd.run "systemctl stop promtail.service; rm /opt/promtail/etc/positions.yaml"
salt-ssh -E "loki-(front1|front2|reader1|reader2|writer1|writer2).tst.example.com" cmd.run "systemctl stop loki; rm -rf /opt/loki"
salt-ssh redis1.tst.example.com cmd.run "redis-cli flushall"
salt-ssh -E "loki-(minio1|minio2|minio3|minio4|minio5|minio6|minio7|minio8).tst.example.com" cmd.run "systemctl stop minio; rm -rf /opt/minio/data/*/.*; rm -rf /opt/minio/data/*/*;"

salt-ssh loki-minio1.tst.example.com state.apply minio.buckets
salt-ssh -E "loki-(front1|front2|reader1|reader2|writer1|writer2).tst.example.com" state.apply loki.systemd
sleep 60

salt-ssh web1.tst.example.com cmd.run "systemctl start promtail.service"
sleep 360

salt-ssh -E "loki-minio(1|2|3|4|5|6|7|8).tst.example.com" cmd.run "echo 'set server minio-data/loki-minio1 state drain' | socat stdio /run/haproxy/admin.sock; echo 'set server minio-data/loki-minio2 state drain' | socat stdio /run/haproxy/admin.sock; echo 'set server minio-data/loki-minio3 state drain' | socat stdio /run/haproxy/admin.sock; echo 'set server minio-data/loki-minio4 state drain' | socat stdio /run/haproxy/admin.sock"
salt-ssh loki-minio1.tst.example.com cmd.run "minio-client admin decommission start local http://loki-minio{1...4}.tst.example.com:9000/opt/minio/data/disk{1...4}"
sleep 600

salt-ssh -E "loki-minio(1|2|3|4).tst.example.com" cmd.run "systemctl stop minio"
salt-ssh -E "loki-minio(1|2|3|4|5|6|7|8).tst.example.com" cmd.run "echo 'set server minio-data/loki-minio1 state ready' | socat stdio /run/haproxy/admin.sock; echo 'set server minio-data/loki-minio2 state ready' | socat stdio /run/haproxy/admin.sock; echo 'set server minio-data/loki-minio3 state ready' | socat stdio /run/haproxy/admin.sock; echo 'set server minio-data/loki-minio4 state ready' | socat stdio /run/haproxy/admin.sock" 
```
