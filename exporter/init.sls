{%- from "exporter/macro.jinja" import main %}

{%- for name, data in pillar.get("exporter", {}).items() %}
  {% set type = data.pop("type", "generic") %}
  {% if pillar.get("exporter_type", type) == type and name is match(pillar.get("exporter_name", name)) %}
    {{ main(type, name, data) }} 
  {% endif %}
{%- endfor %}
