{% if pillar["asterisk_archive"] is defined and "host" in pillar["asterisk_archive"] %}
{% if pillar["acme"] is defined %}
{% set acme = pillar['acme'].keys() | first %}
{% set host = pillar["asterisk_archive"]["host"] %}

{% if not salt['file.directory_exists']('/opt/acme') %}
  {%- include "acme/init.sls" with context %}
{% endif %}

/opt/acme/home/{{ acme }}/verify_and_issue.sh asterisk {{ host }}:
  cmd.run:
    - shell: /bin/bash

{% endif %}
{% endif %}


