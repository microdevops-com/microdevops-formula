{% if pillar['disk_alert'] is defined and pillar['disk_alert'] is not none and pillar['disk_alert']['enabled'] is defined and pillar['disk_alert']['enabled'] is not none and pillar['disk_alert']['enabled'] %}

  {%- if salt['file.directory_exists']('/opt/sysadmws-utils/disk_alert') %}
    {%- if pillar['disk_alert']['config'] is defined and pillar['disk_alert']['config'] is not none %}
swsu_v0_disk_alert_config_managed:
  file.managed:
    - name: '/opt/sysadmws-utils/disk_alert/disk_alert.conf'
    - mode: 0644
    - user: root
    - group: root
    - contents: {{ pillar['disk_alert']['config'] | yaml_encode }}
    {%- endif %}
  {%- endif %}

  {%- if salt['file.directory_exists']('/opt/sysadmws/disk_alert') %}
    {%- if pillar['disk_alert']['config'] is defined and pillar['disk_alert']['config'] is not none %}
swsu_v1_disk_alert_config_managed:
  file.managed:
    - name: '/opt/sysadmws/disk_alert/disk_alert.conf'
    - mode: 0644
    - user: root
    - group: root
    - contents: {{ pillar['disk_alert']['config'] | yaml_encode }}
    {%- endif %}

swsu_v1_disk_alert_cron_managed:
  cron.present:
    - name: '/opt/sysadmws/disk_alert/disk_alert.sh'
    - identifier: disk_alert
    - user: root
    - minute: '*/5'
  {%- endif %}

{% else %}
nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured for a minion of this type, so nothing has been done. But it is OK.
{% endif %}
