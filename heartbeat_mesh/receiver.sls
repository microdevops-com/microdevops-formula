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

heartbeat_mesh_systemd_unit:
  file.managed:
    - name: /etc/systemd/system/heartbeat_mesh_receiver.service
    - mode: 644
    - contents: |
        [Unit]
        Description=Microdevops Heartbeat Mesh Receiver Service

        [Service]
        ExecStart=/opt/sysadmws/heartbeat_mesh/receiver.py
        Environment=PYTHONUNBUFFERED=1
        Restart=on-failure
        Type=notify

        [Install]
        WantedBy=default.target

heartbeat_mesh_systemd_daemon_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/heartbeat_mesh_receiver.service

heartbeat_mesh_receiver_service_restart:
  module.run:
    - name: service.restart
    - m_name: heartbeat_mesh_receiver
    - onchanges:
      - file: /opt/sysadmws/heartbeat_mesh/receiver.yaml

{% endif %}
