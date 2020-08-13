{% if pillar['rancher'] is defined and pillar['rancher'] is not none %}

  {%- if grains['fqdn'] in pillar['rancher']['command_hosts'] %}
install_cmd_1:
  cmd.run:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/helm.sh repo add rancher-stable https://releases.rancher.com/server-charts/stable'

install_cmd_2:
  cmd.run:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/helm.sh repo update'

install_cmd_3:
  cmd.run:
    - shell: /bin/bash
    - name: 'openssl verify -CAfile /opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_ca.cer /opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_fullchain.cer 2>&1 | grep -q -i -e error -e cannot; [ ${PIPESTATUS[1]} -eq 0 ] && /opt/acme/home/acme_local.sh --cert-file /opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_cert.cer --key-file /opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_key.key --ca-file /opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_ca.cer --fullchain-file /opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_fullchain.cer --issue -d {{ pillar['rancher']['cluster_domain'] }} || true'

install_cmd_4:
  cmd.run:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh describe namespace cattle-system | grep -q "Name:.*cattle-system" || /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh create namespace cattle-system'

install_cmd_5:
  cmd.run:
    - name: |
        /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh -n cattle-system create secret tls tls-rancher-ingress \
          --cert=/opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_fullchain.cer \
          --key=/opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_key.key \
          -o yaml --dry-run | /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh -n cattle-system replace --force -f -

install_cmd_6:
  cron.present:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh -n cattle-system create secret tls tls-rancher-ingress --cert=/opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_fullchain.cer --key=/opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_key.key -o yaml --dry-run | /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh -n cattle-system replace --force -f -'
    - identifier: rancher_update_cert
    - user: root
    - minute: 30
    - hour: 7
    - dayweek: 3

install_cmd_7:
  cmd.run:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh -n cattle-system rollout status deploy/rancher | grep -q "deployment.*rancher.*successfully rolled out" || /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/helm.sh install rancher rancher-stable/rancher --namespace cattle-system --set hostname={{ pillar['rancher']['cluster_domain'] }} --set ingress.tls.source=secret'
  {%- endif %}

{% endif %}
