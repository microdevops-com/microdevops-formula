{% if (pillar['cloud'] is defined) and (pillar['cloud'] is not none) %}
  {%- if (pillar['cloud']['hosts_dns'] is defined) and (pillar['cloud']['hosts_dns'] is not none) %}
    {%- for dns_ip, dns_host in pillar['cloud']['hosts_dns'].items()|sort %}
cloud_hosts_dns_{{ loop.index }}:
  host.present:
    - ip: '{{ dns_ip }}'
    - names:
      - '{{ dns_host }}'
    {%- endfor %}
  {%- endif %}
{% endif %}
