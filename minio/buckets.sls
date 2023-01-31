{% if pillar["minio"] is defined %}
{% set minio_install_path = salt['pillar.get']('minio:install_path', '/usr/local/bin/') %}

minio-client_binary:
  file.managed:
    - name: {{ minio_install_path }}minio-client
    - source: https://dl.min.io/client/mc/release/linux-amd64/mc
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - skip_verify: True
    - retry:
        attempts: 3
        until: True
        interval: 60
        splay: 10

minio-client_alias_set:
  cmd.run:
    - name: {{ minio_install_path }}minio-client alias set local {% if pillar["minio"]["ssl"]-%} https {%- else -%} http {%- endif -%} ://localhost:9000 {{ pillar["minio"]["environment"]["MINIO_ROOT_USER"] }} {{ pillar["minio"]["environment"]["MINIO_ROOT_PASSWORD"] }}

minio-client_autocompletion:
  cmd.run:
    - name: {{ minio_install_path }}minio-client --autocompletion

{%- endif %}
11:08:43 bg:0 alex.k@dev1.oxtech.org:~/gitlab.oxtech.org/oxgaming/devops/oxgaming-salt/formulas/microdevops-formula$ cat minio/buckets.sls
{% if pillar["minio"]["buckets"] is defined %}
{% set minio_install_path = salt['pillar.get']('minio:install_path', '/usr/local/bin/') %}
  {%- for bucket in pillar["minio"]["buckets"] %}
create_buckets_{{ loop.index }}:
  cmd.run:
    - name: {{ minio_install_path }}minio-client mb local/{{ bucket }} --ignore-existing
    - shell: /bin/bash
  {%- endfor %}
{%- endif %}
