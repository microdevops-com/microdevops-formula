{% if pillar["minio"]["buckets"] is defined %}
{% set minio_install_path = salt['pillar.get']('minio:install_path', '/usr/local/bin/') %}
  {% if pillar["minio"]["buckets"]["with_versioning"] is defined %}
    {%- for bucket in pillar["minio"]["buckets"]["with_versioning"] %}
create_bucket_{{ bucket }}_with_versioning:
  cmd.run:
    - name: {{ minio_install_path }}minio-client mb local/{{ bucket }} --ignore-existing --with-versioning
    - shell: /bin/bash
    {%- endfor %}
  {%- endif %}
  {% if pillar["minio"]["buckets"]["without_versioning"] is defined %}
    {%- for bucket in pillar["minio"]["buckets"]["without_versioning"] %}
create_bucket_{{ bucket }}_without_versioning:
  cmd.run:
    - name: {{ minio_install_path }}minio-client mb local/{{ bucket }} --ignore-existing
    - shell: /bin/bash
    {%- endfor %}
  {%- endif %}
{%- endif %}
