{% if pillar["disk_alert"] is defined and "enabled" in pillar["disk_alert"] and pillar["disk_alert"]["enabled"] %}

  {%- if "config" in pillar["disk_alert"] %}
disk_alert_dir:
  file.directory:
    - name: /opt/sysadmws/disk_alert
    - user: root
    - group: root
    - mode: 0775

disk_alert_config_managed:
  file.managed:
    - name: /opt/sysadmws/disk_alert/disk_alert.conf
    - mode: 0644
    - user: root
    - group: root
    - contents: {{ pillar["disk_alert"]["config"] | yaml_encode }}
  {%- endif %}

# 240 = 4 minutes, sleep randomly within cron time frame to flatten load on alerta servers
disk_alert_cron_managed:
  cron.present:
    - name: /opt/sysadmws/disk_alert/disk_alert.sh 240
    - identifier: disk_alert
    - user: root
    - minute: "*/5"
  {%- if "cron_disabled" in pillar["disk_alert"] and pillar["disk_alert"]["cron_disabled"] %}
    - commented: True
  {%- endif %}

{% else %}
disk_alert_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured for a minion of this type, so nothing has been done. But it is OK.
{% endif %}
