{% if pillar["minio"] is defined %}
{% set minio_user = salt['pillar.get']('minio:user', 'minio') %}
{% set minio_group = salt['pillar.get']('minio:group', 'minio') %}
{% set minio_download_url = salt['pillar.get']('minio:download_url', 'https://dl.min.io/server/minio/release/linux-amd64/minio') %}
{% set minio_install_path = salt['pillar.get']('minio:install_path', '/usr/local/bin/') %}
{% set dir_volumes = salt['pillar.get']('minio:environment:MINIO_VOLUMES') %}


{{ dir_volumes }}:
  file.directory:
    - user: {{ minio_user }}
    - group: {{ minio_group }}
    - mode: 755
    - makedirs: True
    - recurse:
      - user
      - group

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
#    - unless:
#        # asserts minio is on our path
#        - which minio

{%- endif %}
