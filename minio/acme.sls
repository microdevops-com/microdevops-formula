{% if pillar["minio"] is defined %}
{% if pillar["acme"] is defined and salt['file.directory_exists']('/opt/acme') %}
{% set minio_user = salt['pillar.get']('minio:user') %}
{% set minio_group = salt['pillar.get']('minio:group') %}
{% set acme = pillar['acme'].keys() | first %}


make_file_/opt/acme/home/{{ acme }}/verify_and_issue_for_minio.sh:
  file.managed:
    - name: /opt/acme/home/{{ acme }}/verify_and_issue_for_minio.sh
    - source: salt://{{ slspath }}/files/verify_and_issue_for_minio.sh
    - template: jinja
    - user: root
    - group: root
    - mode: 755
    - context:
        minio_user: {{ minio_user }}
        acme: {{ acme }}

/home/{{ minio_user }}/.minio/certs/cert.crt:
  file.managed:
    - user: {{ minio_user }}
    - group: {{ minio_group }}
    - mode: 0644

/home/{{ minio_user }}/.minio/certs/private.key:
  file.managed:
    - user: {{ minio_user }}
    - group: {{ minio_group }}
    - mode: 0600

/home/{{ minio_user }}/.minio/certs/ca.crt:
  file.managed:
    - user: {{ minio_user }}
    - group: {{ minio_group }}
    - mode: 0644

/home/{{ minio_user }}/.minio/certs/public.crt:
  file.managed:
    - user: {{ minio_user }}
    - group: {{ minio_group }}
    - mode: 0644

run_/opt/acme/home/{{ acme }}/verify_and_issue_for_minio.sh:
  cmd.run:
    - name: /opt/acme/home/{{ acme }}/verify_and_issue_for_minio.sh
    - shell: /bin/bash

{%- endif %}
{%- endif %}

