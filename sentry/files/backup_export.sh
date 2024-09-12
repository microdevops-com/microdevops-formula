#!/bin/bash
docker-compose --file /opt/sentry/docker-compose.yml run --rm -T -e SENTRY_LOG_LEVEL=CRITICAL web export > /opt/sentry/backup/backup.json
#/opt/sentry/scripts/backup.sh global

