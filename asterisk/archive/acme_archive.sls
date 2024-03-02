{% if pillar["asterisk_archive"] is defined and "host" in pillar["asterisk_archive"] %}
  {% if pillar["acme"] is defined %}
    
    {% from "acme/macros.jinja" import verify_and_issue %}

    {% set acme = pillar["acme"].keys() | first %}
    {% set host = pillar["asterisk_archive"]["host"] %}
    
    {% if not salt["file.directory_exists"]("/opt/acme") %}
      {%- include "acme/init.sls" with context %}
    {% endif %}
  
    {{ verify_and_issue(acme, "asterisk", host) }}

  {% endif %}
{% endif %}
