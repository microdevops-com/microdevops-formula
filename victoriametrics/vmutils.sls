{%- import_yaml "victoriametrics/defaults.yaml" as defaults %}

{%- set kind = "vmutils" %}
{%- set vm_name = "main" %}
{%- set vmutils = pillar.get(kind, {}) %}
{%- if vmutils %}
  {%- do vmutils.update({"target": vmutils.get("target", defaults[kind]["target"]).rstrip("/") + "/" }) %}
  {%- set vm_data = {"service": vmutils} %}
  {%- include "victoriametrics/_setup.sls" %}
{%- endif %}
