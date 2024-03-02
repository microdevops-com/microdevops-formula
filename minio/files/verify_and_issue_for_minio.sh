#!/bin/bash

ACME_LOCAL_DOMAIN={{ domain }}
/opt/acme/home/{{ acme }}/acme_local.sh \
  --cert-file {{ homedir }}/.minio/certs/cert.crt \
  --key-file {{ homedir }}/.minio/certs/private.key \
  --ca-file {{ homedir }}/.minio/certs/ca.crt \
  --fullchain-file {{ homedir }}/.minio/certs/public.crt \
  --issue -d ${ACME_LOCAL_DOMAIN} \
  --reloadcmd 'systemctl restart minio.service'
