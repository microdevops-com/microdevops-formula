{% if pillar['netdata'] is defined and pillar['netdata'] is not none and pillar['netdata']['enabled'] is defined and pillar['netdata']['enabled'] is not none and pillar['netdata']['enabled'] %}
    # Set some vars
    {%- set netdata_seconds = pillar['netdata']['seconds'] %}
    {%- set netdata_version = pillar['netdata']['version'] %}
    {%- set netdata_container = pillar['netdata'].get('container', False) %}
    {%- set netdata_mini = pillar['netdata'].get('mini', False) %}
    {%- set netdata_fpinger = pillar['netdata'].get('fpinger', False) %}
    {%- set netdata_fpinger_hosts = pillar['netdata'].get('fpinger_hosts', '') %}
    {%- set hostname_under = grains['fqdn']|replace(".", "_") %}
    {%- set gateway = salt['cmd.shell']("/sbin/ip route | awk '/default/ { print $3 }'") %}
    {%- set netdata_fpinger_hosts = netdata_fpinger_hosts + " " + gateway %}

    {%- if grains['os'] in ['CentOS', 'RedHat'] and grains['osmajorrelease']|int == 6 %}
netdata_newer_git_repo:
  pkg.installed:
    - sources:
      - wandisco-git-release: http://opensource.wandisco.com/centos/6/git/x86_64/wandisco-git-release-6-1.noarch.rpm

netdata_newer_git:
  pkg.latest:
    - refresh: True
    - pkgs:
      - git
      - nss
      - curl
    {%- endif %}
    {% if pillar['netdata']['alt_install'] is defined and pillar['netdata']['alt_install'] is not none and pillar['netdata']['alt_install'] %}
netdata_depencies_installed:
  cmd.script:
    - name: install-required-packages.sh --dont-wait --non-interactive netdata-all
    - source: https://raw.githubusercontent.com/netdata/netdata-demo-site/master/install-required-packages.sh
    {%- else %}
netdata_depencies_installed:
  pkg.installed:
    - pkgs:
      {%- if grains['os'] in ['Ubuntu', 'Debian'] %}
      - zlib1g-dev
      - uuid-dev
      - netcat-openbsd
      - pkg-config
      - libuuid1
      - zlib1g
      - autoconf-archive
      - autogen
        {%- if not netdata_container %}
      - lm-sensors
      - libipmimonitoring-dev
      - freeipmi-tools
        {%- endif %}
      {%- elif grains['os'] in ['CentOS', 'RedHat'] %}
      - zlib-devel
      - libuuid-devel
      - libmnl-devel
      - nmap
      - pkgconfig
      - libuuid
      - zlib
        {%- if not netdata_container %}
      - lm_sensors
      - freeipmi-devel
      - freeipmi
        {%- endif %}
      {%- endif %}
      - gcc
      - make
      - autoconf
      - automake
      - curl
      {%- if grains['osmajorrelease']|int >= 12 and grains['os'] == 'Ubuntu' %}
      - libmnl-dev
      {%- elif grains['os'] == 'Debian' %}
      - libmnl-dev
      {%- endif %}
      {%- if grains['osmajorrelease']|int <= 10 and grains['os'] == 'Ubuntu' %}
      - git-core
      {%- else %}
      - git
      {%- endif %}
    {%- endif %}

    {%- if grains['os'] in ['Ubuntu', 'Debian'] and not netdata_container and grains['virtual'] != "kvm" %}
# Install depencies for bare metal hosts
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
    - source: 'salt://netdata/files/deps/hddtemp'
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
    - source: 'salt://netdata/files/deps/smartmontools'
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

# Install netdata
netdata_repo:
  git.latest:
    - name: https://github.com/firehol/netdata.git
    - rev: {{ netdata_version }}
    - target: /opt/netdata/git
    - force_reset: True
    - force_clone: True

    # Get current installed netdata version
    {%- set netdata_installed_version = salt['cmd.shell']('cd /opt/netdata/git && git rev-parse --verify HEAD') %}
    # If installed version differs from pillar or netdata_force_install set - install netdata
    {%- if (netdata_version != netdata_installed_version) or (pillar['netdata_force_install'] is defined and pillar['netdata_force_install'] is not none and pillar['netdata_force_install']) %}
netdata_install_run:
  cmd.run:
    - cwd: /opt/netdata/git
      {%- if grains['osmajorrelease']|int <= 10 and grains['os'] == 'Ubuntu' %}
    - name: ./netdata-installer.sh --dont-wait --libs-are-really-here --install /opt && service netdata stop
      {%- else %}
    - name: ./netdata-installer.sh --dont-wait --install /opt && service netdata stop
      {%- endif %}
    {%- endif %}

netdata_config_health_alarm:
  file.managed:
    - name: '/opt/netdata/etc/netdata/health_alarm_notify.conf'
    - source: 'salt://netdata/files/health_alarm_notify.conf_host'
    - mode: 0644

netdata_config_netdata:
  file.managed:
    - name: '/opt/netdata/etc/netdata/netdata.conf'
    {%- if netdata_mini %}
    - source: 'salt://netdata/files/netdata.conf_mini'
    {%- else %}
    - source: 'salt://netdata/files/netdata.conf_host'
    {%- endif %}
    - mode: 0644
    - template: jinja
    - defaults:
        host_name: {{ hostname_under }}
        history_seconds: {{ netdata_seconds }}
    {%- if netdata_container %}
        container_block: |
          [plugins]
          	cgroups = no
          	proc = no
    {%- else %}
        container_block: ''
    {%- endif %}

    {%- if netdata_container %}
netdata_config_pythond:
  file.managed:
    - name: '/opt/netdata/etc/netdata/python.d.conf'
    - source: 'salt://netdata/files/python.d.conf_container'
    - mode: 0644
    {%- endif %}

    # Check postgres and configure agent if exists
    {%- if (grains['roles'] is defined) and ('postgresql' in grains['roles']) %}
      {%- set post_pass = salt['cmd.shell']("grep postgres.pass /etc/salt/minion | sed -e 's/^postgres.pass: .\\(.*\\)./\\1/'") %}
netdata_config_postgresql:
  file.managed:
    - name: '/opt/netdata/etc/netdata/python.d/postgres.conf'
    - source: 'salt://netdata/files/deps/postgres.conf'
    - mode: 0660
    - template: jinja
    - defaults:
        postgresql_pass: {{ post_pass }}
    {%- endif %}

    {%- if grains['os'] in ['Ubuntu', 'Debian'] and not netdata_container and grains['virtual'] != "kvm" %}
netdata_config_smartd:
  file.managed:
    - name: '/opt/netdata/etc/netdata/python.d/smartd_log.conf'
    - source: 'salt://netdata/files/deps/smartd_log.conf'
    - mode: 0660
    {%- endif %}
    
    {%- if netdata_fpinger %}
# Netdata needs its own modified fping, should be run after netdata install
netdata_depencies_fping:
  cmd.run:
    - cwd: /root
    - name: '[ ! -x /usr/local/bin/fping ] && /opt/netdata/usr/libexec/netdata/plugins.d/fping.plugin install; true'

netdata_config_fping:
  file.managed:
    - name: '/opt/netdata/etc/netdata/fping.conf'
    - source: 'salt://netdata/files/deps/fping.conf'
    - mode: 0644
    - template: jinja
    - defaults:
        fping_hosts: {{ netdata_fpinger_hosts }}
    {%- endif %}
  
  # Custom fping alarms (higher thresholds), maybe /custom/ location doesn't work, need to check
netdata_dir_custom_health:
  file.directory:
    - name: /opt/netdata/etc/netdata/health.d/custom
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

netdata_config_custom_fping:
  file.managed:
    - name: '/opt/netdata/etc/netdata/health.d/custom/fping.conf'
    - source: 'salt://netdata/files/alarms/fping.conf'
    - mode: 0664

netdata_config_custom_fping_reload:
  cmd.run:
    - cwd: /root
    - name: 'killall -USR2 netdata; true'
    - onchanges:
      - file: '/opt/netdata/etc/netdata/health.d/custom/fping.conf'

    # Custom configs for monitoring

    # Custom thresholds for high load disks
    {%- if (pillar['monitoring'] is defined) and (pillar['monitoring'] is not none) %}
      {%- if (pillar['monitoring']['high_load_disks'] is defined) and (pillar['monitoring']['high_load_disks'] is not none) %}
        {%- for server_disk in pillar['monitoring']['high_load_disks']|sort %}
          {%- if (pillar['monitoring']['high_load_disks'][server_disk]['alarm_minutes'] is defined) and (pillar['monitoring']['high_load_disks'][server_disk]['alarm_minutes'] is not none) %}
netdata_config_custom_high_load_disks_{{ loop.index }}:
  file.managed:
    - name: '/opt/netdata/etc/netdata/health.d/custom/disk_{{ loop.index }}.conf'
    - source: 'salt://netdata/files/alarms/disk.conf'
    - mode: 0664
    - template: jinja
    - defaults:
        disk_name: {{ server_disk }}
        alarm_mins: {{ pillar['monitoring']['high_load_disks'][server_disk]['alarm_minutes'] }}

netdata_config_custom_high_load_disks_reload_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: 'killall -USR2 netdata'
    - onchanges:
      - file: '/opt/netdata/etc/netdata/health.d/custom/disk_{{ loop.index }}.conf'
          {%- endif %}
        {%- endfor %}
      {%- endif %}

      # Ipmi workarounds
      {%- if (pillar['monitoring']['ipmi_events_ok'] is defined) and (pillar['monitoring']['ipmi_events_ok'] is not none) %}
netdata_config_custom_ipmi_events_ok:
  file.managed:
    - name: '/opt/netdata/etc/netdata/health.d/ipmi.conf'
    - source: 'salt://netdata/files/alarms/ipmi.conf'
    - mode: 0664
    - template: jinja
    - defaults:
        ipmi_events_ok: {{ pillar['monitoring']['ipmi_events_ok'] }}

netdata_config_custom_pmi_events_ok_reload:
  cmd.run:
    - cwd: /root
    - name: 'killall -USR2 netdata'
    - onchanges:
      - file: '/opt/netdata/etc/netdata/health.d/ipmi.conf'
      {%- endif %}
    {%- endif %}

# Netdata service enable
netdata_start_script_file:
  file.managed:
    {%- if grains['init'] == 'systemd' %}
    - name: '/etc/systemd/system/netdata.service'
    - source: '/opt/netdata/git/system/netdata.service'
    - mode: 0644
    {%- elif grains['os'] in ['CentOS', 'RedHat'] and grains['osmajorrelease']|int == 6 %}
    - name: '/etc/init.d/netdata'
    - source: '/opt/netdata/git/system/netdata-init-d'
    - mode: 0755
    {%- elif grains['init'] in ['upstart','sysvinit'] %}
    - name: '/etc/init.d/netdata'
    - source: '/opt/netdata/git/system/netdata-lsb'
    - mode: 0755
    {%- else %}
    'do not know which script to use'
    {%- endif %}

netdata_service_running:
  service.running:
    - watch:
      - file: '/opt/netdata/etc/netdata/netdata.conf'
    {%- if netdata_fpinger %}
      - file: '/opt/netdata/etc/netdata/fping.conf'
    {%- endif %}
      - file: '/opt/netdata/etc/netdata/health_alarm_notify.conf'
    {%- if netdata_container %}
      - file: '/opt/netdata/etc/netdata/python.d.conf'
    {%- endif %}
    {%- if (grains['roles'] is defined) and ('postgresql' in grains['roles']) %}
      - file: '/opt/netdata/etc/netdata/python.d/postgres.conf'
    {%- endif %}
    {%- if grains['os'] in ['Ubuntu', 'Debian'] and not netdata_container and grains['virtual'] != "kvm" %}
      - file: '/opt/netdata/etc/netdata/python.d/smartd_log.conf'
    {%- endif %}
    - name: netdata
    - enable: True

{% else %}
mysql_replica_checker_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured by pillar, so nothing has been done. But it is OK.
{% endif %}
