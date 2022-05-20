{%- if pillar["freeipa"] is defined %}
verify and issue le certificate:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["freeipa"]["acme_account"] }}/verify_and_issue.sh freeipa {{ pillar["freeipa"]["hostname"] }}"

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

install certificates:
  cmd.run:
    - shell: /bin/bash
    - name: sleep 10; docker exec freeipa-{{ pillar["freeipa"]["hostname"] }} bash -c "echo {{ pillar['freeipa']['ds_password'] }} | ipa-server-certinstall -w -d /acme/freeipa_{{ pillar['freeipa']['hostname'] }}_key.key /acme/freeipa_{{ pillar['freeipa']['hostname'] }}_cert.cer --pin=''"

ipactl restart:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec freeipa-{{ pillar["freeipa"]["hostname"] }} bash -c "ipactl restart"
{%- endif %}
