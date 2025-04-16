{% if pillar["asterisk"] is defined and "version" in pillar["asterisk"] %}
{% if pillar["acme"] is defined %}

{% set domain = pillar["asterisk"]["acme"]["domain"] %}
{% set parts = domain.split('.') %}
{% set acme_account = parts[-2] ~ '.' ~ parts[-1] %}
{% set user = pillar["asterisk"]["user"] %}
{% set group = pillar["asterisk"]["group"] %}
{% set cert_file = salt['pillar.get']('asterisk:acme:cert-file', '/etc/asterisk/keys/asterisk.crt') %}
{% set key_file = salt['pillar.get']('asterisk:acme:key-file', '/etc/asterisk/keys/asterisk.key') %}
{% set ca_file = salt['pillar.get']('asterisk:acme:ca-file', '/etc/asterisk/keys/asterisk_ca.pem') %}
{% set fullchain_file = salt['pillar.get']('asterisk:acme:fullchain-file', '/etc/asterisk/keys/asterisk_fullchain.pem') %}
{% set reloadcmd = salt['pillar.get']('asterisk:acme:reloadcmd', 'echo ok') %}

{% if not salt['file.directory_exists']('/opt/acme') %}
  {%- include "acme/init.sls" with context %}
{% endif %}


{{ "/".join(cert_file.split("/")[:-1]) }}:
  file.directory:
    - user: {{ user }}
    - group: {{ group }}
    - dir_mode: 755

make_file_/opt/acme/{{ acme_account }}/home/verify_and_issue_for_asterisk.sh:
  file.managed:
    - name: /opt/acme/{{ acme_account }}/home/verify_and_issue_for_asterisk.sh
    - mode: 0700
    - contents: |
        #!/bin/bash
        if [[ "$1" == "" ]]; then
          echo -e >&2 "ERROR: Use verify_and_issue_for_asterisk.sh APP DOMAIN DOMAIN2 DOMAIN3...DOMAIN100"
          exit 1
        fi
        ACME_LOCAL_APP="$1"
        ACME_LOCAL_DOMAIN="$2"
        printf -v DOMAINS -- " -d %s" "${@:2}"
        /opt/acme/{{ acme_account }}/home/acme_local.sh \
          --cert-file {{ cert_file }} \
          --key-file {{ key_file }} \
          --ca-file {{ ca_file }} \
          --fullchain-file {{ fullchain_file }} \
          --issue ${DOMAINS} \
          --reloadcmd '{{ reloadcmd }}'

run_/opt/acme/{{ acme_account }}/home/verify_and_issue_for_asterisk.sh:
  cmd.run:
    - name: /opt/acme/{{ acme_account }}/home/verify_and_issue_for_asterisk.sh asterisk {{ domain }}
    - shell: /bin/bash
    - success_stdout:
       - Domains not changed.
       - Skip, Next renewal time is
       - Add '--force' to force to renew.
    - success_retcodes: [2]

{% endif %}
{% endif %}
