{%- if pillar["freeipa"] is defined %}

  {% from "acme/macros.jinja" import verify_and_issue %}

  {{ verify_and_issue(pillar["freeipa"]["acme_account"], "freeipa", pillar["freeipa"]["hostname"]) }}

install wget:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec freeipa-{{ pillar["freeipa"]["hostname"] }} bash -c "dnf install wget -y"

install root ca certificate 1:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec freeipa-{{ pillar["freeipa"]["hostname"] }} bash -c "wget https://letsencrypt.org/certs/isrgrootx1.pem | ipa-cacert-manage install isrgrootx1.pem -n ISRGRootCAX1 -t C,,"

install root ca certificate 2:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec freeipa-{{ pillar["freeipa"]["hostname"] }} bash -c "wget https://letsencrypt.org/certs/lets-encrypt-r3.pem | ipa-cacert-manage install lets-encrypt-r3.pem -n ISRGRootCAR3 -t C,,"

ipa-certupdate:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec freeipa-{{ pillar["freeipa"]["hostname"] }} bash -c "ipa-certupdate"

script_for_cert_check_and_install:
  file.managed:
    - name: /opt/freeipa/{{ pillar['freeipa']['hostname'] }}/certificate_check_and_install.sh
    - contents: |
        #!/bin/bash

        fp_of_cert_in_file="$(echo | openssl s_client -connect {{ pillar['freeipa']['hostname'] }}:443 |& openssl x509 -fingerprint -noout -sha256)"
        fp_of_cert_installed="$(openssl x509 -noout -in /opt/acme/cert/freeipa_{{ pillar['freeipa']['hostname'] }}_cert.cer -fingerprint -sha256)"

        if [[ "${fp_of_cert_in_file}" == "${fp_of_cert_installed}" ]]; then
          exit 0;
        else
          docker exec freeipa-{{ pillar["freeipa"]["hostname"] }} bash -c "echo {{ pillar['freeipa']['ds_password'] }} | ipa-server-certinstall -w -d /acme/freeipa_{{ pillar['freeipa']['hostname'] }}_key.key /acme/freeipa_{{ pillar['freeipa']['hostname'] }}_cert.cer --pin=''"
          docker exec freeipa-{{ pillar["freeipa"]["hostname"] }} bash -c "ipactl restart"
        fi
    - mode: 700

cert_check_and_install:
  cmd.run:
    - shell: /bin/bash
    - name: /opt/freeipa/{{ pillar['freeipa']['hostname'] }}/certificate_check_and_install.sh

create cron for check and install certs:
  cron.present:
    - name: /opt/freeipa/{{ pillar['freeipa']['hostname'] }}/certificate_check_and_install.sh
    - identifier: checking freeipa certificates and reload freeipa
    - user: root
    - minute: 10
    - hour: 1
{%- endif %}
