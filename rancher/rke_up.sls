{% if pillar["rancher"] is defined %}

  {%- if grains["fqdn"] in pillar["rancher"]["command_hosts"] %}
rke_up:
  cmd.run:
    - name: rke up --config /opt/rancher/clusters/{{ pillar["rancher"]["cluster_name"] }}/cluster.yml
  {%- endif %}

{% endif %}
