#!/bin/bash

ACME_LOCAL_DOMAIN=$(hostname -f)
/opt/acme/{{ acme }}/home/acme_local.sh \
  --cert-file {{ certificate_dir }}/{{ certificate_name }}.crt \
  --key-file {{ certificate_dir }}/{{ certificate_name }}.key \
  --ca-file {{ certificate_dir }}/{{ certificate_name }}_ca.pem \
  --fullchain-file {{ certificate_dir }}/{{ certificate_name }}_fullchain.pem \
  --issue -d ${ACME_LOCAL_DOMAIN} \
  --reloadcmd '{{ reloadcmd }}'
