{% if pillar["heartbeat_mesh"] is defined and "sender" in pillar["heartbeat_mesh"] %}
  {%- if salt["file.directory_exists"]("/opt/sysadmws/heartbeat_mesh") %}
heartbeat_mesh_sender_config:
  file.serialize:
    - name: /opt/sysadmws/heartbeat_mesh/sender.yaml
    - user: root
    - group: root
    - mode: 644
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ pillar["heartbeat_mesh"]["sender"]["config_override"] if "config_override" in pillar["heartbeat_mesh"]["sender"] else pillar["heartbeat_mesh"]["sender"]["config"] }}

heartbeat_mesh_sender_cron_managed:
  cron.present:
    - identifier: heartbeat_mesh_sender
    - name: /opt/sysadmws/heartbeat_mesh/sender.py
    - user: root
    - minute: "{{ pillar["heartbeat_mesh"]["sender"]["cron"] }}"

  {%- endif %}
{% endif %}
