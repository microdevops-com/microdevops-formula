{% if pillar["rancher"] is defined %}
  {%- for rancher_key, rancher_val in pillar["rancher"].items() %}
    {%- if "run" in rancher_val and rancher_val["run"] %}
      {%- if grains["fqdn"] in rancher_val["command_hosts"] %}
rke_up:
  cmd.run:
    - name: rke up --config /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/cluster.yml

      {%- endif %}
    {%- endif %}
  {%- endfor %}
{% endif %}
