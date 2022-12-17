#!/bin/bash
docker-compose --file /opt/sentry/docker-compose.yml stop
docker run --rm --volumes-from sentry-self-hosted-clickhouse-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-clickhouse-1.tar"
docker run --rm --volumes-from sentry-self-hosted-web-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-web-1.tar"
docker run --rm --volumes-from sentry-self-hosted-kafka-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-kafka-1.tar"
docker run --rm --volumes-from sentry-self-hosted-nginx-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-nginx-1.tar"
docker run --rm --volumes-from sentry-self-hosted-postgres-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-postgres-1.tar"
docker run --rm --volumes-from sentry-self-hosted-redis-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-redis-1.tar"
docker run --rm --volumes-from sentry-self-hosted-smtp-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-smtp-1.tar"
docker run --rm --volumes-from sentry-self-hosted-symbolicator-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-symbolicator-1.tar"
docker run --rm --volumes-from sentry-self-hosted-zookeeper-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-zookeeper-1.tar"
docker-compose --file /opt/sentry/docker-compose.yml up -d
