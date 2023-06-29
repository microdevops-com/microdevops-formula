#!/bin/bash

ACME_LOCAL_DOMAIN=$(hostname -f)
if openssl verify -CAfile {{ certificate_dir }}/{{ certificate_name }}_ca.pem {{ certificate_dir }}/{{ certificate_name }}_fullchain.pem 2>&1 | grep -q -i -e error -e cannot; then
  /opt/acme/{{ acme }}/home/acme_local.sh \
    --cert-file {{ certificate_dir }}/{{ certificate_name }}.crt \
    --key-file {{ certificate_dir }}/{{ certificate_name }}.key \
    --ca-file {{ certificate_dir }}/{{ certificate_name }}_ca.pem \
    --fullchain-file {{ certificate_dir }}/{{ certificate_name }}_fullchain.pem \
    --issue -d ${ACME_LOCAL_DOMAIN} \
    --reloadcmd '{{ reloadcmd }}'
else
  echo openssl verify OK
fi   
