{% if pillar["minio"] is defined %}
{% set minio_user = salt['pillar.get']('minio:user', 'minio') %}
{% set minio_group = salt['pillar.get']('minio:group', 'minio') %}
{% set minio_limit_nofile = salt['pillar.get']('minio:limit_nofile', '65536') %}
{% set environment = salt['pillar.get']('minio:environment') %}


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


minio_etc_default:
  file.managed:
    - name: /etc/default/minio
    - user: root
    - group: root
    - mode: 644
    - contents:
{% for key, val in environment.items() %}
{% if val == True %}{% set val = '=on' %}{% elif val == False %}{% set val = '=off' %}{% else %}{% set val = '=' + val | string() %}{% endif %}
      - {{ key }}{{ val }}
{% endfor %}


minio_enable_service:
  service.enabled:
    - name: minio

minio_start_service:
  service.running:
    - name: minio

{%- endif %}