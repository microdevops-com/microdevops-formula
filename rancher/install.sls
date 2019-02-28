{% if pillar['rancher'] is defined and pillar['rancher'] is not none %}

  {%- if grains['fqdn'] in pillar['rancher']['command_hosts'] %}
install_cmd_1:
  cmd.run:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh -n kube-system describe serviceaccount tiller | grep -q "Name:.*tiller" || /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh -n kube-system create serviceaccount tiller'

install_cmd_2:
  cmd.run:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh describe clusterrolebinding tiller | grep -q "Name:.*tiller" || /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh create clusterrolebinding tiller --clusterrole cluster-admin  --serviceaccount=kube-system:tiller'

install_cmd_3:
  cmd.run:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/helm.sh init --service-account tiller'

install_cmd_4:
  cmd.run:
    - name: 'until /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh -n kube-system  rollout status deploy/tiller-deploy | grep -q "successfully rolled out"; do echo .; done'

install_cmd_5:
  cmd.run:
    - name: 'until /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/helm.sh version | grep -q "v2.11.0"; do echo .; done'

install_cmd_6:
  cmd.run:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/helm.sh repo add rancher-stable https://releases.rancher.com/server-charts/stable'

install_cmd_7:
  cmd.run:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/helm.sh repo update'

install_cmd_8:
  cmd.run:
    - shell: /bin/bash
    - name: 'openssl verify -CAfile /opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_ca.cer /opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_fullchain.cer 2>&1 | grep -q -i -e error; [ ${PIPESTATUS[1]} -eq 0 ] && /opt/acme/home/acme_local.sh --cert-file /opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_cert.cer --key-file /opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_key.key --ca-file /opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_ca.cer --fullchain-file /opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_fullchain.cer --issue -d {{ pillar['rancher']['cluster_domain'] }} || true'

install_cmd_9:
  cmd.run:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh describe namespace cattle-system | grep -q "Name:.*cattle-system" || /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh create namespace cattle-system'

install_cmd_10:
  cmd.run:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh -n cattle-system describe secret tls-rancher-ingress | grep -q "Name:.*tls-rancher-ingress" || /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh -n cattle-system create secret tls tls-rancher-ingress --cert=/opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_fullchain.cer --key=/opt/acme/cert/rancher_{{ pillar['rancher']['cluster_name'] }}_key.key'

install_cmd_11:
  cmd.run:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh -n cattle-system rollout status deploy/rancher | grep -q "deployment.*rancher.*successfully rolled out" || /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/helm.sh install rancher-stable/rancher --name rancher --namespace cattle-system --set hostname={{ pillar['rancher']['cluster_domain'] }} --set ingress.tls.source=secret'
  {%- endif %}

{% endif %}
