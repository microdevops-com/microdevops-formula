{% if pillar['disk_alert'] is defined and pillar['disk_alert'] is not none %}

  {%- if salt['file.directory_exists']('/opt/sysadmws-utils/disk_alert') %}
swsu_v0_disk_alert_config_managed:
  file.managed:
    - name: '/opt/sysadmws-utils/disk_alert/disk_alert.conf'
    - mode: 0644
    - user: root
    - group: root
    - contents: {{ pillar['disk_alert'] | yaml_encode }}
  {%- endif %}

  {%- if salt['file.directory_exists']('/opt/sysadmws/disk_alert') %}
swsu_v1_disk_alert_config_managed:
  file.managed:
    - name: '/opt/sysadmws/disk_alert/disk_alert.conf'
    - mode: 0644
    - user: root
    - group: root
    - contents: {{ pillar['disk_alert'] | yaml_encode }}
  {%- endif %}

{% endif %}
