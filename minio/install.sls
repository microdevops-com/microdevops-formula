{% if pillar["minio"] is defined %}
{% set minio_user = salt['pillar.get']('minio:user', 'minio') %}
{% set minio_group = salt['pillar.get']('minio:group', 'minio') %}
{% set minio_download_url = salt['pillar.get']('minio:download_url', 'https://dl.min.io/server/minio/release/linux-amd64/minio') %}
{% set minio_install_path = salt['pillar.get']('minio:install_path', '/usr/local/bin/') %}
{% set working_directory = salt['pillar.get']('minio:working_directory', '/usr/local/') %}

  {% if "http" not in salt['pillar.get']('minio:environment:MINIO_VOLUMES') %}
{{ salt['pillar.get']('minio:environment:MINIO_VOLUMES') }}:
  file.directory:
    - user: {{ minio_user }}
    - group: {{ minio_group }}
    - mode: 755
    - makedirs: True
    - recurse:
      - user
      - group
  {% endif %}


minio_binary:
  file.managed:
    - name: {{ minio_install_path }}minio
    - source: {{ minio_download_url }}
    - source_hash: {{ minio_download_url }}.sha256sum
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - retry:
        attempts: 3
        until: True
        interval: 60
        splay: 10


  {% if pillar["minio"]["disk_pool"] is defined %}
    {%- for folder, device in pillar["minio"]["disk_pool"].items() %}
mount_{{ loop.index }}:
  mount.mounted:
    - name: {{ working_directory }}{{ folder }}
    - device: {{ device }}
    - fstype: xfs
    - opts: "defaults,noatime"
    - dump: 0
    - pass_num: 2
    - persist: True
    - mkmnt: True
    {%- endfor %}
set_permissions:
  file.directory:
    - name: {{ working_directory }}
    - user: {{ minio_user }}
    - group: {{ minio_group }}
    - mode: 755
    - recurse:
      - user
      - group
  {%- endif %}
{%- endif %}
