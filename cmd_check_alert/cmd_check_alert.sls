{%- if pillar['cmd_check_alert'] is defined and pillar['cmd_check_alert'] is not none %}
  {%- if salt['file.directory_exists']('/opt/sysadmws/notify_devilry') and
         salt['file.directory_exists']('/opt/sysadmws/cmd_check_alert') %}
swsu_v1_cmd_check_alert_config_managed:
  file.serialize:
    - dataset_pillar: cmd_check_alert
    - name: '/opt/sysadmws/cmd_check_alert/cmd_check_alert.conf.json'
    - formatter: json
    - mode: 0600
    - user: root
    - group: root

swsu_v1_cmd_check_alert_cron_managed:
  cron.present:
    - identifier: 'cmd_check_alert'
    - name: '/opt/sysadmws/cmd_check_alert/cmd_check_alert.sh'
    - user: root
    - minute: "{{ pillar['cmd_check_alert']['config']['cron']['minute'] }}"
    {%- endif %}

{%- else %}
cmd_check_alert_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: cmd_check_alert pillar not found or sysadmws-utils not installed
{%- endif %}
