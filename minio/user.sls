{% if pillar["minio"] is defined %}
{% set minio_user = salt['pillar.get']('minio:user', 'minio') %}
{% set minio_group = salt['pillar.get']('minio:group', 'minio') %}


minio_group:
  group.present:
    - name: {{ minio_group }}

minio_user:
  user.present:
    - name: {{ minio_user }}
    - groups: 
      - {{ minio_group }}


{%- endif %}