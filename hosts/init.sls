{%- if pillar["hosts"] is defined %}

  {%- if "present" in pillar["hosts"] %}
    {%- for ip, rest in pillar["hosts"]["present"].items() %}

      {%- if rest is mapping and 'names' in rest %}
hosts_present_{{ loop.index }}:
  host.present:
    - ip: {{ ip }}
    - names: {{ rest['names'] }}
    - clean: {{ rest.get('clean', False) }}
        {%- if 'comment' in rest %}
    - comment: {{ rest['comment'] }}
        {%- endif %}

      {%- else %}

hosts_present_{{ loop.index }}:
  host.present:
    - ip: {{ ip }}
    - names: {{ rest }}
      {%- endif %}
    {%- endfor %}

  {%- endif %}


  {%- if "absent" in pillar["hosts"] %}
    {%- for ip, rest in pillar["hosts"]["present"].items() %}
      {%- if rest is mapping and 'names' in rest %}
hosts_absent_{{ loop.index }}:
  host.absent:
    - ip: {{ ip }}
    - names: {{ rest['names'] }}
      {%- endif %}
    {%- endfor %}
  {%- endif %}


{%- endif %}
