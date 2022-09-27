#!/bin/bash

ACME_LOCAL_DOMAIN=$(hostname -f)
if openssl verify -CAfile /home/{{ minio_user }}/.minio/certs/ca.crt /home/{{ minio_user }}/.minio/certs/public.crt 2>&1 | grep -q -i -e error -e cannot; then
  /opt/acme/home/oxtech.org/acme_local.sh \
    --cert-file /home/{{ minio_user }}/.minio/certs/cert.crt \
    --key-file /home/{{ minio_user }}/.minio/certs/private.key \
    --ca-file /home/{{ minio_user }}/.minio/certs/ca.crt \
    --fullchain-file /home/{{ minio_user }}/.minio/certs/public.crt \
    --issue -d ${ACME_LOCAL_DOMAIN} \
    --reloadcmd 'systemctl restart minio.service'
else
  echo openssl verify OK
fi   