{% if pillar["cmd_check_alert"] is defined %}
cmd_check_alert_dir:
  file.directory:
    - name: /opt/sysadmws/cmd_check_alert/checks
    - user: root
    - group: root
    - mode: 0775
    - makedirs: True

# Remove common config and cron, we've switched to separate config and cron per check pillar
cmd_check_alert_commong_config_absent:
  file.absent:
    - name: /opt/sysadmws/cmd_check_alert/cmd_check_alert.yaml

cmd_check_alert_common_cron_absent:
  cron.absent:
    - identifier: cmd_check_alert
    - name: /opt/sysadmws/cmd_check_alert/cmd_check_alert.py
    - user: root

  {%- for check_group_name, check_group_params in pillar["cmd_check_alert"].items() %}
cmd_check_alert_config_managed_{{ loop.index }}:
  file.serialize:
    - name: /opt/sysadmws/cmd_check_alert/checks/{{ check_group_name }}.yaml
    - mode: 0600
    - user: root
    - group: root
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ check_group_params["config"] }}

cmd_check_alert_cron_managed_{{ loop.index }}:
  cron.present:
    - identifier: cmd_check_alert_{{ check_group_name }}
    - name: /opt/sysadmws/cmd_check_alert/cmd_check_alert.py --yaml checks/{{ check_group_name }}.yaml
    - user: root
    - minute: "{{ check_group_params["cron"] }}"

  {%- endfor %}

{% else %}
cmd_check_alert_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured for a minion of this type, so nothing has been done. But it is OK.

{% endif %}
