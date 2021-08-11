{% if pillar["hosts"] is defined %}
  {%- if "present" in pillar["hosts"] %}
    {%- for ip, names in pillar["hosts"]["present"].items() %}
hosts_present_{{ loop.index }}:
  host.present:
    - ip: {{ ip }}
    - names: {{ names }}

    {%- endfor %}
  {%- endif %}
{% endif %}
