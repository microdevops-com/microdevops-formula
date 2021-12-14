{% if pillar["heartbeat_mesh"] is defined and "receiver" in pillar["heartbeat_mesh"] %}
heartbeat_mesh_receiver_dir:
  file.directory:
    - name: /opt/sysadmws/heartbeat_mesh
    - user: root
    - group: root
    - mode: 0775

heartbeat_mesh_receiver_config:
  file.serialize:
    - name: /opt/sysadmws/heartbeat_mesh/receiver.yaml
    - user: root
    - group: root
    - mode: 644
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ pillar["heartbeat_mesh"]["receiver"]["config"] }}

heartbeat_mesh_receiver_service_restart:
  module.run:
    - name: service.restart
    - m_name: heartbeat_mesh_receiver
    - onchanges:
      - file: /opt/sysadmws/heartbeat_mesh/receiver.yaml

{% endif %}
