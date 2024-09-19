#!/bin/bash
{%- if   salt['pkg.version_cmp'](pillar["sentry"]["version"],'24.1.0') >= 0 %}
# for version is greater or equal to 24.1.0
#/opt/sentry/scripts/backup.sh global --no-report-self-hosted-issues
[[ -f /opt/sentry/.env.custom ]] && docker-compose --env-file /opt/sentry/.env.custom --file /opt/sentry/docker-compose.yml run --rm -T -e SENTRY_LOG_LEVEL=CRITICAL web export global > /opt/sentry/sentry/backup.json || docker-compose --file /opt/sentry/docker-compose.yml run --rm -T -e SENTRY_LOG_LEVEL=CRITICAL web export global > /opt/sentry/sentry/backup.json    
{%- elif salt['pkg.version_cmp'](pillar["sentry"]["version"],'24.1.0')  < 0 %}
# for version is less than 24.1.0
[[ -f /opt/sentry/.env.custom ]] && docker-compose --env-file /opt/sentry/.env.custom --file /opt/sentry/docker-compose.yml run --rm -T -e SENTRY_LOG_LEVEL=CRITICAL web export > /opt/sentry/sentry/backup.json || docker-compose --file /opt/sentry/docker-compose.yml run --rm -T -e SENTRY_LOG_LEVEL=CRITICAL web export > /opt/sentry/sentry/backup.json
{%- endif %}

