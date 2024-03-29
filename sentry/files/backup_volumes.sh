#!/bin/bash
mkdir -p /opt/sentry/backup/volumes/
docker-compose --file /opt/sentry/docker-compose.yml run --rm -T -e SENTRY_LOG_LEVEL=CRITICAL web export > /opt/sentry/backup/backup.json
docker-compose --file /opt/sentry/docker-compose.yml stop
docker run --rm --volumes-from sentry-self-hosted-clickhouse-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-clickhouse-1.tar /var/lib/clickhouse /var/log/clickhouse-server
docker run --rm --volumes-from sentry-self-hosted-web-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-web-1.tar /data
docker run --rm --volumes-from sentry-self-hosted-kafka-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-kafka-1.tar /var/lib/kafka/data /etc/kafka/secrets /var/lib/kafka/log
docker run --rm --volumes-from sentry-self-hosted-nginx-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-nginx-1.tar /var/cache/nginx
docker run --rm --volumes-from sentry-self-hosted-postgres-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-postgres-1.tar /var/lib/postgresql/data
docker run --rm --volumes-from sentry-self-hosted-redis-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-redis-1.tar /data
docker run --rm --volumes-from sentry-self-hosted-smtp-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-smtp-1.tar /var/spool/exim4 /var/log/exim4
docker run --rm --volumes-from sentry-self-hosted-symbolicator-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-symbolicator-1.tar /data
docker run --rm --volumes-from sentry-self-hosted-zookeeper-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-zookeeper-1.tar /var/lib/zookeeper/data  /var/lib/zookeeper/log
docker-compose --file /opt/sentry/docker-compose.yml up -d
