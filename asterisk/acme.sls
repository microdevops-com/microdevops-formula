{% if pillar["asterisk"] is defined and "version" in pillar["asterisk"] %}
{% if pillar["acme"] is defined %}
{% set acme = pillar['acme'].keys() | first %}
{% set user = pillar["asterisk"]["user"] %}
{% set group = pillar["asterisk"]["group"] %}
{% set certificate_name = salt['pillar.get']('asterisk:acme:certificate_name', 'asterisk') %}
{% set certificate_dir = salt['pillar.get']('asterisk:acme:certificate_dir', '/etc/asterisk/keys') %}
{% set reloadcmd = salt['pillar.get']('asterisk:acme:reloadcmd', 'echo ok') %}

{% if not salt['file.directory_exists']('/opt/acme') %}
  {%- include "acme/init.sls" with context %}
{% endif %}

{{ certificate_dir }}:
  file.directory:
    - user: {{ user }}
    - group: {{ group }}
    - dir_mode: 755


make_file_/opt/acme/home/{{ acme }}/verify_and_issue_for_asterisk.sh:
  file.managed:
    - name: /opt/acme/home/{{ acme }}/verify_and_issue_for_asterisk.sh
    - source: salt://{{ slspath }}/files/scripts/verify_and_issue_for_asterisk.sh
    - user: root
    - group: root
    - template: jinja
    - mode: 755
    - context:
        acme: {{ acme }}
        certificate_name: {{ certificate_name }}
        certificate_dir: {{ certificate_dir }}
        reloadcmd: {{ reloadcmd }}

run_/opt/acme/home/{{ acme }}/verify_and_issue_for_asterisk.sh:
  cmd.run:
    - name: /opt/acme/home/{{ acme }}/verify_and_issue_for_asterisk.sh
    - shell: /bin/bash

{% endif %}
{% endif %}


