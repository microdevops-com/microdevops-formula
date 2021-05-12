{% if pillar["heartbeat_mesh"] is defined and "sender" in pillar["heartbeat_mesh"] %}
  {%- if grains["os"] in ["Windows"] %}
heartbeat_mesh_dir:
  file.directory:
    - name: c:/opt/sysadmws/heartbeat_mesh/log
    - makedirs: True

heartbeat_mesh_sender_py:
  file.managed:
    - name: c:/opt/sysadmws/heartbeat_mesh/sender.py
    - source: https://raw.githubusercontent.com/sysadmws/sysadmws-utils/master/heartbeat_mesh/sender.py
    - skip_verify: True

heartbeat_mesh_sender_task:
  cmd.run:
    - name: |
        c:\windows\system32\schtasks.exe /create /tn heartbeat_mesh_sender /ru SYSTEM /sc MINUTE /tr "c:\salt\bin\python.exe c:\opt\sysadmws\heartbeat_mesh\sender.py" /np /f
  {%- endif %}

heartbeat_mesh_sender_dir:
  file.directory:
    - name: /opt/sysadmws/heartbeat_mesh
  {%- if grains["os"] not in ["Windows"] %}
    - user: root
    - group: root
    - mode: 0775
  {%- endif %}

heartbeat_mesh_sender_config:
  file.serialize:
    - name: /opt/sysadmws/heartbeat_mesh/sender.yaml
  {%- if grains["os"] not in ["Windows"] %}
    - user: root
    - group: root
    - mode: 644
  {%- endif %}
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ pillar["heartbeat_mesh"]["sender"]["config_override"] if "config_override" in pillar["heartbeat_mesh"]["sender"] else pillar["heartbeat_mesh"]["sender"]["config"] }}

  {%- if grains["os"] not in ["Windows"] %}
heartbeat_mesh_sender_cron_managed:
  cron.present:
    - identifier: heartbeat_mesh_sender
    - name: /opt/sysadmws/heartbeat_mesh/sender.py
  {%- if grains["os"] not in ["Windows"] %}
    - user: root
  {%- endif %}
    - minute: "{{ pillar["heartbeat_mesh"]["sender"]["cron"] }}"

  {%- endif %}
{% endif %}
