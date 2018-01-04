{% if (pillar['disk_alert'] is defined) and (pillar['disk_alert'] is not none) %}
disk_alert_config_managed:
  file.managed:
    - name: '/opt/sysadmws-utils/disk_alert/disk_alert.conf'
    - mode: 0600
    - user: root
    - group: root
    - contents: {{ pillar['disk_alert'] | yaml_encode }}
{% endif %}
