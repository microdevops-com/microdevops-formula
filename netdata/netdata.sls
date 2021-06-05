{% if pillar["netdata"] is defined %}

remove_old_type_netdata:
  cmd.run:
    - name: |
        [ -d /opt/netdata/git ] && ( service netdata stop; killall -9 netdata; rm -rf /opt/netdata ) || true

    # Set some vars
  {%- set netdata_seconds = pillar["netdata"]["seconds"] %}
  {%- set netdata_mini = pillar["netdata"].get("mini", False) %}
  {%- set postgresql = pillar["netdata"].get("postgresql", False) %}
  {%- set sensors = pillar["netdata"].get("sensors", False) %}
  {%- set hostname_under = grains["fqdn"]|replace(".", "_") %}

  {% if grains["oscodename"] not in ["precise"] %}
# Basic depencies
netdata_depencies_installed_netdata:
  cmd.script:
    - name: install-required-packages.sh --dont-wait --non-interactive netdata
    - source: https://raw.githubusercontent.com/netdata/netdata/master/packaging/installer/install-required-packages.sh

  {%- endif %}

      # If sensors - install even more
  {%- if sensors %}
netdata_depencies_installed_sensors_1:
  cmd.script:
    - name: install-required-packages.sh --dont-wait --non-interactive sensors
    - source: https://raw.githubusercontent.com/netdata/netdata/master/packaging/installer/install-required-packages.sh

    {%- if grains["os"] in ["Ubuntu", "Debian"] %}
netdata_depencies_installed_sensors_2:
  pkg.installed:
    - pkgs:
      - libipmimonitoring-dev
      - freeipmi-tools

hddtemp:
  pkg:
    - installed
  service:
    - enable: True
    - running
    - watch:
      - pkg: hddtemp
      - file: /etc/default/hddtemp

/etc/default/hddtemp:
  file.managed:
    - source: salt://netdata/files/deps/hddtemp
    - require:
      - pkg: hddtemp

smartmontools:
  pkg:
    - installed
  service:
    - enable: True
    - running
    - watch:
      - pkg: smartmontools
      - file: /etc/default/smartmontools

/etc/default/smartmontools:
  file.managed:
    - source: salt://netdata/files/deps/smartmontools
    - require:
      - pkg: smartmontools

netdata_dir_smartd:
  file.directory:
    - name: /var/log/smartd
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

    {%- endif %}
  {%- endif %}
    
# Install netdata
netdata_kickstart:
  cmd.script:
    - name: kickstart-static64.sh --dont-wait --stable-channel --no-updates --reinstall
    - source: https://raw.githubusercontent.com/netdata/netdata/master/packaging/installer/kickstart-static64.sh

netdata_config_health_alarm:
  file.managed:
    - name: /opt/netdata/etc/netdata/health_alarm_notify.conf
    - source: salt://netdata/files/health_alarm_notify.conf_host
    - mode: 0644

netdata_config_netdata:
  file.managed:
    - name: /opt/netdata/etc/netdata/netdata.conf
  {%- if netdata_mini %}
    - source: salt://netdata/files/netdata.conf_mini
  {%- else %}
    - source: salt://netdata/files/netdata.conf_host
  {%- endif %}
    - mode: 0644
    - template: jinja
    - defaults:
        host_name: {{ hostname_under }}
        history_seconds: {{ netdata_seconds }}
    # Disable some unneeded features if sensors are not enabled
  {%- if sensors %}
        container_block: ''
  {%- else %}
        container_block: |
          [plugins]
          	cgroups = no
          	proc = no
  {%- endif %}

    # Disable some unneeded features if sensors are not enabled
  {%- if not sensors %}
netdata_config_pythond:
  file.managed:
    - name: /opt/netdata/etc/netdata/python.d.conf
    - source: salt://netdata/files/python.d.conf_container
    - mode: 0644
  {%- endif %}

    # Check postgres and configure agent if exists
  {%- if postgresql %}
    {%- set post_pass = salt["cmd.shell"]("grep postgres.pass /etc/salt/minion | sed -e 's/^postgres.pass: .\\(.*\\)./\\1/'") %}
netdata_config_postgresql:
  file.managed:
    - name: /opt/netdata/etc/netdata/python.d/postgres.conf
    - source: salt://netdata/files/deps/postgres.conf
    - mode: 0660
    - template: jinja
    - defaults:
        postgresql_pass: {{ post_pass }}
  {%- endif %}

    # Additional sensor tuning if enabled
  {%- if sensors %}
    {%- if grains["os"] in ["Ubuntu", "Debian"] %}
netdata_config_smartd:
  file.managed:
    - name: '/opt/netdata/etc/netdata/python.d/smartd_log.conf'
    - source: 'salt://netdata/files/deps/smartd_log.conf'
    - mode: 0660

    {%- endif %}
  {%- endif %}
    
{% else %}
netdata_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured by pillar, so nothing has been done. But it is OK.

{% endif %}
