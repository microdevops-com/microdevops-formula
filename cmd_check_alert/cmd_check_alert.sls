{% if pillar["cmd_check_alert"] is defined %}
  {%- if salt["file.directory_exists"]("/opt/sysadmws/cmd_check_alert") %}
cmd_check_alert_config_managed:
  file.managed:
    - name: /opt/sysadmws/cmd_check_alert/cmd_check_alert.yaml
    - mode: 0600
    - user: root
    - group: root
    - source: {{ pillar["cmd_check_alert"]["config_file"] }}

cmd_check_alert_cron_managed:
  cron.present:
    - identifier: cmd_check_alert
    - name: /opt/sysadmws/cmd_check_alert/cmd_check_alert.py
    - user: root
    - minute: "{{ pillar["cmd_check_alert"]["cron"] }}"

  {%- endif %}

{% else %}
cmd_check_alert_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured for a minion of this type, so nothing has been done. But it is OK.

{% endif %}
