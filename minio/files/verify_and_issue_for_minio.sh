#!/bin/bash

ACME_LOCAL_DOMAIN={{ domain }}
[[ -f "/opt/acme/home/{{ acme }}/acme_local.sh" ]] && /opt/acme/home/{{ acme }}/acme_local.sh || /opt/acme/{{ acme }}/home/acme_local.sh \
  --cert-file {{ homedir }}/.minio/certs/cert.crt \
  --key-file {{ homedir }}/.minio/certs/private.key \
  --ca-file {{ homedir }}/.minio/certs/ca.crt \
  --fullchain-file {{ homedir }}/.minio/certs/public.crt \
  --issue -d ${ACME_LOCAL_DOMAIN} \
  --reloadcmd 'systemctl restart minio.service'
