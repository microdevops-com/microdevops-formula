{% if pillar["pxc"] is defined %}
pxc_repo_deb:
  pkg.installed:
    - sources:
      - percona-release: https://repo.percona.com/apt/percona-release_latest.generic_all.deb

pxc_release_disable_all:
  cmd.run:
    - name: percona-release disable all
    - require:
      - pkg: pxc_repo_deb

  {%- for repo, component in pillar["pxc"]["repos"].items() %}
pxc_release_enable_repo_{{ loop.index }}:
  cmd.run:
    - name: percona-release enable {{ repo }} {{ component }}
    - require:
      - pkg: pxc_repo_deb

  {%- endfor %}

# Install prereqs after repo enabling - to refresh only once
pxc_prereq_pkgs:
  pkg.installed:
    - refresh: True
    - pkgs:
        - gnupg2
        - xinetd
        - debconf-utils
        - nmap
        - zstd

# Predefine server root passwords before package installed
  {%- if "debconf" in pillar["pxc"] %}
    {%- for pkg_name, pkg_debconf in pillar["pxc"]["debconf"].items() %}
pxc_debconf_{{ loop.index }}:
  debconf.set:
    - name: {{ pkg_name }}
    - data:
      {%- for debconf_key, debconf_val in pkg_debconf.items() %}
        '{{ debconf_key }}': {'type': '{{ debconf_val["type"] }}', 'value': '{{ debconf_val["value"]|replace("__root_password__", pillar["pxc"]["root_password"]) }}'}

      {%- endfor %}
    {%- endfor %}
  {%- endif %}

# Install packages
  {%- for pkg, version in pillar["pxc"]["pkgs"].items() %}
    {%- if version == "latest" %}
pxc_pkg_{{ loop.index }}:
  pkg.latest:
    - pkgs:
      - {{ pkg }}

    {%- else %}
pxc_pkg_{{ loop.index }}:
  pkg.installed:
    - pkgs:
      - {{ pkg }}: '{{ version }}*'

    {%- endif %}
  {%- endfor %}

# Fix dir perms in case they are in mounted volumes
pxc_log_dir:
  file.directory:
    - name: /var/log/mysql
    - user: mysql
    - group: adm
    - mode: 750

pxc_lib_dir:
  file.directory:
    - name: /var/lib/mysql
    - user: mysql
    - group: mysql
    - mode: 750

  {%- if grains["init"] == "systemd" %}
pxc_mysql_systemd_override:
  file.managed:
    - name: /etc/systemd/system/mysql.service.d/override.conf
    - makedirs: True
    - user: root
    - group: root
    - mode: 644
    - contents: |
        [Service]
        LimitNOFILE=infinity
        LimitMEMLOCK=infinity
        OOMScoreAdjust=-500
  module.run:
    - name: service.systemctl_reload
    - onchanges:
      - file: /etc/systemd/system/mysql.service.d/override.conf
    - watch_in:
      - service: pxc_mysql_service
  {%- endif %}

pxc_mysql_service:
  service.running:
    - name: mysql
    - enable: True

pxc_debian_conf:
  file.managed:
    - name: /etc/mysql/debian.cnf
    - user: root
    - group: root
    - mode: 0600
    - contents: |
        [client]
        host     = localhost
        user     = root
        password = {{ pillar["pxc"]["root_password"] }}
        socket   = /var/run/mysqld/mysqld.sock
        [mysql_upgrade]
        host     = localhost
        user     = root
        password = {{ pillar["pxc"]["root_password"] }}
        socket   = /var/run/mysqld/mysqld.sock

  {%- if not salt["file.file_exists"]("/root/.my.cnf") %}
pxc_create_symlink_debian_sys_maint_to_root:
  file.symlink:
    - name: /root/.my.cnf
    - target: /etc/mysql/debian.cnf

  {%- endif %}

# We do not use salt mysql modules as they are very buggy
  {%- if "clustercheck_install" in pillar["pxc"] and pillar["pxc"]["clustercheck_install"] %}
pxc_clustercheck_sql_1:
  cmd.run:
    - name: |
        mysql -e "CREATE USER IF NOT EXISTS 'clustercheck'@'localhost';"
    - require:
      - service: pxc_mysql_service

pxc_clustercheck_sql_2:
  cmd.run:
    - name: |
        mysql -e "ALTER USER 'clustercheck'@'localhost' IDENTIFIED BY '{{ pillar["pxc"]["clustercheck_password"] }}';"
    - require:
      - service: pxc_mysql_service

pxc_clustercheck_sql_3:
  cmd.run:
    - name: |
        mysql -e "GRANT PROCESS ON *.* TO 'clustercheck'@'localhost';"
    - require:
      - service: pxc_mysql_service

pxc_xinetd_config:
  file.managed:
    - name: /etc/xinetd.d/clustercheck
    - contents: |
        # default: on
        # description: clustercheck
        service clustercheck
        {
        	disable = no
        	flags = REUSE
        	socket_type = stream
        	port = 9200
        	wait = no
        	user = nobody
        	server = /usr/bin/clustercheck
        	server_args = clustercheck {{ pillar["pxc"]["clustercheck_password"] }} 1
        	log_on_failure += USERID
        	only_from = 0.0.0.0/0
        	per_source = UNLIMITED
        }

pxc_clustercheck_etc_services:
  file.line:
    - name: /etc/services
    - mode: ensure
    - after: "# Local services"
    - content: |
        clustercheck	9200/tcp			# percona xtradb clustercheck

pxc_xinetd_service:
  module.run:
    - name: service.restart
    - m_name: xinetd
    - onchanges:
      - file: /etc/xinetd.d/clustercheck
      - file: /etc/services

  {%- endif %}

pxc_pmm_sql_1:
  cmd.run:
    - name: |
        mysql -e "CREATE USER IF NOT EXISTS 'pmm'@'localhost';"
    - require:
      - service: pxc_mysql_service

pxc_pmm_sql_2:
  cmd.run:
    - name: |
        mysql -e "ALTER USER 'pmm'@'localhost' IDENTIFIED BY '{{ pillar["pxc"]["pmm_password"] }}';"
    - require:
      - service: pxc_mysql_service

pxc_pmm_sql_3:
  cmd.run:
    - name: |
        mysql -e "GRANT SELECT, PROCESS, SUPER, REPLICATION CLIENT, RELOAD ON *.* TO 'pmm'@'localhost';"
    - require:
      - service: pxc_mysql_service

pxc_pmm_sql_4:
  cmd.run:
    - name: |
        mysql -e "FLUSH PRIVILEGES;"
    - require:
      - service: pxc_mysql_service

{% endif %}
