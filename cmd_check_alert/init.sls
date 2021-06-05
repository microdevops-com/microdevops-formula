{% if pillar["cmd_check_alert"] is defined %}

  {%- set sensu_plugins_needed = [] %}

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
    {%- if "install_sensu-plugins" in check_group_params %}
      {%- for plugin in check_group_params["install_sensu-plugins"] %}
        {%- if plugin not in sensu_plugins_needed %}
          {%- do sensu_plugins_needed.append(plugin) %}
        {%- endif %}
      {%- endfor %}
    {%- endif %}
  {%- endfor %}

  {%- if sensu_plugins_needed|length > 0 %}
    {%- if grains["os_family"] == "Debian" %}
      {%- if grains["oscodename"] not in ["precise"] %}
sensu-plugins_repo:
  pkgrepo.managed:
    - humanname: Sensu Plugins
    - name: deb https://packagecloud.io/sensu/community/{{ grains["os"]|lower }}/ {{ grains["oscodename"] }} main
    - file: /etc/apt/sources.list.d/sensu_community.list
    - key_url: https://packagecloud.io/sensu/community/gpgkey
    - clean_file: True

      {%- endif %}

    {%- elif grains["os_family"] == "RedHat" %}
sensu-plugins_repo:
  cmd.script:
    - name: script.rpm.sh
    - source: https://packagecloud.io/install/repositories/sensu/community/script.rpm.sh

    {%- endif %}

    {%- if grains["oscodename"] not in ["precise"] %}
sensu-plugins_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
        - sensu-plugins-ruby

      {%- for plugin in sensu_plugins_needed %}
sensu-plugins_install_{{ loop.index }}:
  cmd.run:
    - name: sensu-install -p {{ plugin }}

        {%- if plugin == "disk-checks" %}
sensu-plugins_install_{{ loop.index }}_patch_smart_1:
  file.managed:
    - name: /opt/sensu-plugins-ruby/embedded/lib/ruby/gems/2.4.0/gems/sensu-plugins-disk-checks-5.1.4/bin/check-smart.rb
    - source: salt://cmd_check_alert/files/check-smart.rb
    - create: False
    - show_changes: True

        {%- endif %}
      {%- endfor %}
    {%- endif %}

  {%- endif %}

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
    - serializer_opts:
      - width: 1024 # otherwise it will split long commands in multiple lines
    - dataset: {{ check_group_params["config"] }}

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

    {%- if "install_cvescan" in check_group_params %}
      # snapd is not working on bionic inside lxc
      {%- if grains["oscodename"] == "focal" or (grains["oscodename"] == "bionic" and grains["virtual"] != "lxc"|lower) %}
cmd_check_alert_snapd_installed:
  pkg.installed:
    - pkgs:
      - snapd

cvescan_installed:
  cmd.run:
    - name: snap install cvescan

      {%- endif %}
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
