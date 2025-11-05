#!/bin/bash
# see another example: /opt/sentry/scripts/backup.sh global --no-report-self-hosted-issues
if [[ -f /opt/sentry/.env.custom ]]; then
  docker-compose --env-file /opt/sentry/.env.custom --file /opt/sentry/docker-compose.yml run --rm -T -e SENTRY_LOG_LEVEL=CRITICAL web export global > /opt/sentry/sentry/backup.json
else
  docker-compose                                    --file /opt/sentry/docker-compose.yml run --rm -T -e SENTRY_LOG_LEVEL=CRITICAL web export global > /opt/sentry/sentry/backup.json
fi
