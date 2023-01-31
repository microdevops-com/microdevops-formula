{% if pillar["minio"]["buckets"] is defined %}
{% set minio_install_path = salt['pillar.get']('minio:install_path', '/usr/local/bin/') %}
  {%- for bucket in pillar["minio"]["buckets"] %}
create_buckets_{{ loop.index }}:
  cmd.run:
    - name: {{ minio_install_path }}minio-client mb local/{{ bucket }} --ignore-existing
    - shell: /bin/bash
  {%- endfor %}
{%- endif %}
