{%- if pillar["sysctl"] is defined %}
  {%- set config = pillar["sysctl"].get("config",{}) %}

sysctl_pkg:
  pkg.installed:
    - name: {{ config.get("pkg","procps") }}
    - failhard: True

  {%- for key, values in pillar["sysctl"].items() if key != "config" %}
    {%- for name, value in values.items() %}
sysctl_{{ name }}_{{ value }}:
  sysctl.present:
    - name: {{ name }}
    - value: {{ value }}
      {%- if key != "default" %}
    - config: {{ key }}
      {%- endif %}
    {%- endfor %}
  {%- endfor %}
{%- endif %}
