{% if pillar['rancher'] is defined and pillar['rancher'] is not none %}

  {%- if grains['fqdn'] == pillar['rancher']['command_host'] %}
rke_up:
  cmd.run:
    - name: 'rke up --config /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/cluster.yml'
  {%- endif %}

{% endif %}
