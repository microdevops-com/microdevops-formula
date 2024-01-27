{%- if pillar["bootstrap"] is defined and "service" in pillar["bootstrap"] %}
  {%- for action, services in pillar["bootstrap"]["service"].items() %}
    {%- for name, opts in services.items() %}
{{ name }}:
  service.{{ action }}:
    {{ opts }}
    {%- endfor %}
  {%- endfor %}
{%- endif %}
