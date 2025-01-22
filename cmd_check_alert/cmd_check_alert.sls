{% if pillar["cmd_check_alert"] is defined %}
cmd_check_alert_dir:
  file.directory:
    - name: /opt/sysadmws/cmd_check_alert/checks
    - user: root
    - group: root
    - mode: 0775
    - makedirs: True

  {%- for check_group_name, check_group_params in pillar["cmd_check_alert"].items() if check_group_name not in ["hostname_override"] %}
    {%- if "hostname_override" in pillar["cmd_check_alert"] %}
      {%- do check_group_params["config"].update({"hostname_override": pillar["cmd_check_alert"]["hostname_override"]}) %}
    {%- endif %}
    # There is some bug in serializer that causes int config keys to serialize as strings under salt-ssh and as ints under salt, which leads to flapping of config file
    # Fix by forcing severity_per_retcode to string
    # defaults
    {%- if "defaults" in check_group_params["config"] and "severity_per_retcode" in check_group_params["config"]["defaults"] %}
      {%- set new_severity_per_retcode = {} %}
      {%- for retcode, severity in check_group_params["config"]["defaults"]["severity_per_retcode"].items() %}
        {%- do new_severity_per_retcode.update({retcode|string: severity}) %}
      {%- endfor %}
      {%- do check_group_params["config"]["defaults"].update({"severity_per_retcode": {}}) %}
      {%- do check_group_params["config"]["defaults"]["severity_per_retcode"].update(new_severity_per_retcode) %}
    {%- endif %}
    # checks
    {%- if "checks" in check_group_params["config"] %}
      {%- for check_name, check_params in check_group_params["config"]["checks"].items() %}
        {%- if "severity_per_retcode" in check_params %}
          {%- set new_severity_per_retcode = {} %}
          {%- for retcode, severity in check_params["severity_per_retcode"].items() %}
            {%- do new_severity_per_retcode.update({retcode|string: severity}) %}
          {%- endfor %}
          {%- do check_group_params["config"]["checks"][check_name].update({"severity_per_retcode": {}}) %}
          {%- do check_group_params["config"]["checks"][check_name]["severity_per_retcode"].update(new_severity_per_retcode) %}
        {%- endif %}
        # Also apply cmd_override over cmd here
        {%- if "cmd_override" in check_params %}
          {%- do check_group_params["config"]["checks"][check_name].update({"cmd": check_params["cmd_override"]}) %}
        {%- endif %}
      {%- endfor %}
    {%- endif %}
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
    - serializer_opts:
      - width: 1024 # otherwise it will split long commands in multiple lines
    - dataset: {{ check_group_params["config"] | tojson }}

cmd_check_alert_cron_managed_{{ loop.index }}:
  cron.present:
    - identifier: cmd_check_alert_{{ check_group_name }}
    - name: /opt/sysadmws/cmd_check_alert/cmd_check_alert.py --yaml checks/{{ check_group_name }}.yaml
    - user: root
    {%- if "minute" in check_group_params["cron"] or "hour" in check_group_params["cron"] or "daymonth" in check_group_params["cron"] or "month" in check_group_params["cron"] or "dayweek" in check_group_params["cron"] %}
      {%- if "minute" in check_group_params["cron"] %}
    - minute: "{{ check_group_params["cron"]["minute"] }}"
      {%- endif %}
      {%- if "hour" in check_group_params["cron"] %}
    - hour: "{{ check_group_params["cron"]["hour"] }}"
      {%- endif %}
      {%- if "daymonth" in check_group_params["cron"] %}
    - daymonth: "{{ check_group_params["cron"]["daymonth"] }}"
      {%- endif %}
      {%- if "month" in check_group_params["cron"] %}
    - month: "{{ check_group_params["cron"]["month"] }}"
      {%- endif %}
      {%- if "dayweek" in check_group_params["cron"] %}
    - dayweek: "{{ check_group_params["cron"]["dayweek"] }}"
      {%- endif %}
    {%- else %}
    - minute: "{{ check_group_params["cron"] }}"
    {%- endif %}

    {%- if "files" in check_group_params %}
      {%- set a_loop = loop %}
      {%- for file_name, file_data_items in check_group_params["files"].items() %}
        {%- set contents_list = [] %}
        {%- for file_data_item_name, file_data_item_data in file_data_items.items()|sort %}
          {%- do contents_list.append(file_data_item_data) %}
        {%- endfor %}
cmd_check_alert_file_managed_{{ loop.index }}_{{ a_loop.index }}:
  file.managed:
    - name: {{ file_name }}
    - contents: {{ contents_list | json }}

      {%- endfor %}
    {%- endif %}

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
