{% if pillar["minio"] is defined %}
{% set minio_user = salt['pillar.get']('minio:user', 'minio') %}
{% set minio_group = salt['pillar.get']('minio:group', 'minio') %}
{% set minio_limit_nofile = salt['pillar.get']('minio:limit_nofile', '65536') %}
{% set environment = salt['pillar.get']('minio:environment') %}
{% set minio_install_path = salt['pillar.get']('minio:install_path', '/usr/local/bin/') %}
{% set working_directory = salt['pillar.get']('minio:working_directory', '/usr/local/') %}
{% set env_file = salt['pillar.get']('minio:env_file', '/etc/default/minio') %}


minio_systemd_service:
  file.managed:
    - name: /etc/systemd/system/minio.service
    - source: salt://{{ slspath }}/files/minio.service.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - context:
        minio_user: {{ minio_user }}
        minio_group: {{ minio_group }}
        minio_limit_nofile: {{ minio_limit_nofile }}
        minio_install_path: {{ minio_install_path }}
        working_directory: {{ working_directory }}
        env_file: {{ env_file }}

  {% if salt['pillar.get']('minio:delayed_start_for') is defined %}
{% set delayed_start_for = salt['pillar.get']('minio:delayed_start_for') %}
minio_systemd_service_override_for_delayed_start:
  file.managed:
    - name: /etc/systemd/system/minio.service.d/override.conf
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - contents: |
        [Service]
        ExecStartPre=
        ExecStartPre=/bin/bash -c "if [ -z \"${MINIO_VOLUMES}\" ]; then echo \"Variable MINIO_VOLUMES not set in /etc/default/minio\"; exit 1; fi; /bin/sleep {{ delayed_start_for }}"
  {% endif %}

systemctl_daemon_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - shell: /bin/bash


minio_etc_default:
  file.managed:
    - name: {{ env_file }}
    - user: {{ minio_user }}
    - group: {{ minio_group }}
    - mode: 644
    - contents:
{% for key, val in environment.items() %}
{% if val == True %}{% set val = '=on' %}{% elif val == False %}{% set val = '=off' %}{% else %}{% set val = '=' + val | string() %}{% endif %}
      - {{ key }}{{ val }}
{% endfor %}

minio_service_enable_and_start:
  service.running:
    - name: minio
    - enable: true

minio_service_restart:
  cmd.run:
    - name: systemctl restart minio
    - shell: /bin/bash

{%- endif %}
