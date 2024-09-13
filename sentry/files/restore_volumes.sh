#!/bin/bash
[[ -f /opt/sentry/.env.custom ]] && docker-compose --file /opt/sentry/docker-compose.yml --env-file /opt/sentry/.env.custom stop || docker-compose --file /opt/sentry/docker-compose.yml stop
  docker run --rm --volumes-from sentry-self-hosted-clickhouse-1	-v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-clickhouse-1.tar"
  docker run --rm --volumes-from sentry-self-hosted-web-1		-v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-web-1.tar"
  docker run --rm --volumes-from sentry-self-hosted-kafka-1		-v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-kafka-1.tar"
  docker run --rm --volumes-from sentry-self-hosted-nginx-1		-v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-nginx-1.tar"
  docker run --rm --volumes-from sentry-self-hosted-postgres-1		-v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-postgres-1.tar"
  docker run --rm --volumes-from sentry-self-hosted-redis-1		-v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-redis-1.tar"
  docker run --rm --volumes-from sentry-self-hosted-smtp-1		-v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-smtp-1.tar"
  docker run --rm --volumes-from sentry-self-hosted-symbolicator-1	-v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-symbolicator-1.tar"
  ## updates for version 24.8.0
  if docker ps -a --format '{{.Names}}' | grep -q 'sentry-self-hosted-zookeeper-1'; then 
    docker run --rm --volumes-from sentry-self-hosted-zookeeper-1	-v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-zookeeper-1.tar"
  fi
  if docker ps -a --format '{{.Names}}' | grep -q 'sentry-self-hosted-vroom-1'; then
    docker run --rm --volumes-from sentry-self-hosted-vroom-1		-v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-vroom-1.tar"
  fi
  ##
[[ -f /opt/sentry/.env.custom ]] && docker-compose --file /opt/sentry/docker-compose.yml --env-file /opt/sentry/.env.custom up -d || docker-compose --file /opt/sentry/docker-compose.yml up -d

