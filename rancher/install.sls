{% if pillar["rancher"] is defined %}
  {%- for rancher_key, rancher_val in pillar["rancher"].items() %}
    {%- if "run" in rancher_val and rancher_val["run"] %}
      {%- if grains["fqdn"] in rancher_val["command_hosts"] %}
install_cmd_1:
  cmd.run:
    - name: /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/helm.sh repo add rancher-stable https://releases.rancher.com/server-charts/stable

install_cmd_2:
  cmd.run:
    - name: /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/helm.sh repo update

install_cmd_3:
  cmd.run:
    - shell: /bin/bash
    - name: /opt/acme/home/{{ rancher_val["acme_account"] }}/verify_and_issue.sh rancher {{ rancher_val["cluster_domain"] }}

install_cmd_4:
  cmd.run:
    - name: /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/kubectl.sh describe namespace cattle-system | grep -q "Name:.*cattle-system" || /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/kubectl.sh create namespace cattle-system

install_cmd_5:
  cmd.run:
    - name: |
        /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/kubectl.sh -n cattle-system create secret tls tls-rancher-ingress \
          --cert=/opt/acme/cert/rancher_{{ rancher_val["cluster_name"] }}_fullchain.cer \
          --key=/opt/acme/cert/rancher_{{ rancher_val["cluster_name"] }}_key.key \
          -o yaml --dry-run | /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/kubectl.sh -n cattle-system replace --force -f -

install_cmd_6:
  cron.present:
    - name: /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/kubectl.sh -n cattle-system create secret tls tls-rancher-ingress --cert=/opt/acme/cert/rancher_{{ rancher_val["cluster_name"] }}_fullchain.cer --key=/opt/acme/cert/rancher_{{ rancher_val["cluster_name"] }}_key.key -o yaml --dry-run | /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/kubectl.sh -n cattle-system replace --force -f -
    - identifier: rancher_update_cert_{{ rancher_val["cluster_name"] }}
    - user: root
    - minute: 30
    - hour: 7
    - dayweek: 3

install_cmd_7:
  cmd.run:
    - name: /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/kubectl.sh -n cattle-system rollout status deploy/rancher | grep -q "deployment.*rancher.*successfully rolled out" || /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/helm.sh install rancher rancher-stable/rancher --namespace cattle-system --set hostname={{ rancher_val["cluster_domain"] }} --set ingress.tls.source=secret

      {%- endif %}
    {%- endif %}
  {%- endfor %}
{% endif %}
