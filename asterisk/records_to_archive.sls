{% if pillar["asterisk"] is defined and pillar["сluster_asterisk"] is defined and "version" in pillar["asterisk"] %}
{% if pillar["сluster_asterisk"]["ssh_keys"] is defined %}
{% if pillar["сluster_asterisk"]["archive_server"] is defined and "records_to_archive" in pillar["сluster_asterisk"]["archive_server"] %} 

  {% set host_archive = pillar["сluster_asterisk"]["archive_server"]["host_archive"] %}
  {% set user_archive = pillar["сluster_asterisk"]["archive_server"]["user_archive"] %}
  {% set user = pillar["asterisk"]["user"] %}
  {% set group = pillar["asterisk"]["group"] %}
  {% set ssh_file = pillar["сluster_asterisk"]["ssh_keys"]["ssh_file"] %}
  {% set des_dir = pillar["сluster_asterisk"]["archive_server"]["records_to_archive"]["destination_directory"] if pillar["сluster_asterisk"]["archive_server"]["records_to_archive"]["destination_directory"] is defined else '/var/archive' %}

install_lots_from_pip:
  pip.installed:
    - names:
      - paramiko

minio_systemd_service:
  file.managed:
    - name: /var/lib/asterisk/scripts/monitor_to_archive.py
    - source: salt://{{ slspath }}/files/scripts/monitor_to_archive.py
    - template: jinja
    - user: {{ user }}
    - group: {{ group }}
    - mode: 644
    - context:
        host_archive: {{ host_archive }}
        user_archive: {{ user_archive }}
        ssh_file: /var/lib/asterisk/.ssh/{{ ssh_file }}
        des_dir: {{ des_dir }}

cron_asterisk_server_copy_records:
  cron.present:
    - name: /usr/bin/python3 /var/lib/asterisk/scripts/monitor_to_archive.py
    - identifier: copy_records_to_remote_server
    - user: {{ user }}
    - minute: '*/3'

  {% if pillar["сluster_asterisk"]["archive_server"]["records_to_archive"]["delete_old_records_on_asterisk_server_days"] is defined %}
    {% set delete_time = pillar["сluster_asterisk"]["archive_server"]["records_to_archive"]["delete_old_records_on_asterisk_server_days"] %} 
delete_old_records_on_asterisk_server:
  cron.present:
    - name: /usr/bin/find /var/spool/asterisk/monitor/ -type f -mtime +{{ delete_time }} -delete
    - identifier: delete_old_records_on_asterisk_server
    - user: {{ user }}
    - minute: 1
    - hour: 4
  {%- endif %}

{%- endif %}
{%- endif %}
{%- endif %}
