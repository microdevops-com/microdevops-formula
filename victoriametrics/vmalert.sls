{%- set kind = "vmalert" %}
{%- for vm_name, vm_data in pillar.get(kind, {}).items() %}
  {%- include "victoriametrics/_setup.sls" %}
{%- endfor %}

