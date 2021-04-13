{% if pillar["cmd_check_alert"] is defined %}
cmd_check_alert_dir:
  file.directory:
    - name: /opt/sysadmws/cmd_check_alert
    - user: root
    - group: root
    - mode: 0775

cmd_check_alert_mako_module:
  pkg.installed:
    - pkgs:
  {%- if "300" in grains['saltversion']|string %}
        - python3-mako
  {%- else %}
        - python-mako
  {%- endif %}
    - reload_modules: True

  {%- if "300" in grains['saltversion']|string %}
    {%- set mako_installed = salt["cmd.shell"]("dpkg -l 2>/dev/null | grep -e '^ii *python3-mako' | awk '{print $1}'") %}
  {%- else %}
    {%- set mako_installed = salt["cmd.shell"]("dpkg -l 2>/dev/null | grep -e '^ii *python-mako' | awk '{print $1}'") %}
  {%- endif %}
  # Ugly hack: only run this state if make already installed, coz reload_modules doesn't work inside salt-ssh and produces error on first highstate over salt-ssh
  # So it will be run some time later
  {%- if mako_installed == "ii" %}
cmd_check_alert_config_managed:
  file.managed:
    - name: /opt/sysadmws/cmd_check_alert/cmd_check_alert.yaml
    - mode: 0600
    - user: root
    - group: root
    - source: {{ pillar["cmd_check_alert"]["config_file"] }}
    - replace: True
    {%- if "checks" in pillar["cmd_check_alert"] %}
    - template: mako
    - defaults:
        additional_checks: |
          # additional checks added by pillar:
      {%- for check_name, check_val in pillar["cmd_check_alert"]["checks"].items() %}
            {{ check_name }}:
        {%- for check_val_key, check_val_val in check_val.items() %}
              {{ check_val_key }}: {{ check_val_val }}
        {%- endfor %}
      {%- endfor %}
    {%- endif %}
  {%- endif %}

cmd_check_alert_cron_managed:
  cron.present:
    - identifier: cmd_check_alert
    - name: /opt/sysadmws/cmd_check_alert/cmd_check_alert.py
    - user: root
    - minute: "{{ pillar["cmd_check_alert"]["cron"] }}"

{% else %}
cmd_check_alert_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured for a minion of this type, so nothing has been done. But it is OK.

{% endif %}
