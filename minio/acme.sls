{% if pillar["minio"] is defined %}
{% if pillar["acme"] is defined and salt['file.directory_exists']('/opt/acme') %}
{% set domain = salt['pillar.get']('minio:name', '$(hostname -f)') %}
{% set minio_user = salt['pillar.get']('minio:user', 'minio') %}
{% set minio_group = salt['pillar.get']('minio:group', 'minio') %}
{% set acme = pillar['acme'].keys() | first %}

  {%- if salt['pillar.get']('minio:user', 'minio') == 'root' %}
{% set homedir = '/root' %}
  {%- else %}
{% set homedir = '/home/' + salt['pillar.get']('minio:user', 'minio') %}
  {%- endif %}



make_file_/opt/acme/home/{{ acme }}/verify_and_issue_for_minio.sh:
  file.managed:
    - name: /opt/acme/home/{{ acme }}/verify_and_issue_for_minio.sh
    - source: salt://{{ slspath }}/files/verify_and_issue_for_minio.sh
    - template: jinja
    - user: root
    - group: root
    - mode: 755
    - context:
        homedir: {{ homedir }}
        acme: {{ acme }}
        domain: {{ domain }}

create homedir for minio:
  file.directory:
    - names:
      - {{ homedir }}/.minio/certs
      - {{ homedir }}/.minio
    - makedirs: True
    - mode: 700
    - user: {{ minio_user }}
    - group: {{ minio_group }}

run_/opt/acme/home/{{ acme }}/verify_and_issue_for_minio.sh:
  cmd.run:
    - name: /opt/acme/home/{{ acme }}/verify_and_issue_for_minio.sh
    - shell: /bin/bash

{{ homedir }}/.minio/certs/cert.crt:
  file.managed:
    - user: {{ minio_user }}
    - group: {{ minio_group }}
    - mode: 0644

{{ homedir }}/.minio/certs/private.key:
  file.managed:
    - user: {{ minio_user }}
    - group: {{ minio_group }}
    - mode: 0600

{{ homedir }}/.minio/certs/ca.crt:
  file.managed:
    - user: {{ minio_user }}
    - group: {{ minio_group }}
    - mode: 0644

{{ homedir }}/.minio/certs/public.crt:
  file.managed:
    - user: {{ minio_user }}
    - group: {{ minio_group }}
    - mode: 0644

{%- endif %}
{%- endif %}
