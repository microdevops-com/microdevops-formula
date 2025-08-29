{% if pillar["mariadb"] is defined %}
# Set up MariaDB apt repository
mariadb_repo_dir:
  file.directory:
    - name: /etc/apt/sources.list.d
    - makedirs: True

mariadb_repo_key:
  cmd.run:
    - name: |
        curl -fsSL https://mariadb.org/mariadb_release_signing_key.asc | apt-key add -
    - unless: apt-key list | grep -q "MariaDB"

mariadb_keyrings_dir:
  file.directory:
    - name: /etc/apt/trusted.gpg.d

mariadb_keyring_file:
  file.managed:
    - name: /etc/apt/trusted.gpg.d/mariadb-keyring-2019.gpg
    - source: https://supplychain.mariadb.com/mariadb-keyring-2019.gpg
    - skip_verify: True

mariadb_repo:
  file.managed:
    - name: /etc/apt/sources.list.d/mariadb.list
    - contents: |
        # MariaDB Server
        deb [arch=amd64,arm64] https://dlm.mariadb.com/repo/mariadb-server/{{ pillar["mariadb"]["version"]|default("10.11") }}/repo/{{ grains["os"]|lower }} {{ grains["oscodename"] }} main
        # MariaDB Tools
        deb [arch=amd64] http://downloads.mariadb.com/Tools/{{ grains["os"]|lower }} {{ grains["oscodename"] }} main
    - require:
      - cmd: mariadb_repo_key

# Install prereqs after repo setup
mariadb_prereq_pkgs:
  pkg.installed:
    - refresh: True
    - pkgs:
        - gnupg2
        - nmap
    - require:
      - file: mariadb_repo

# Install packages
  {%- for pkg, version in pillar["mariadb"]["pkgs"].items() %}
    {%- if version == "latest" %}
mariadb_pkg_{{ loop.index }}:
  pkg.latest:
    - pkgs:
      - {{ pkg }}
    - require:
      - pkg: mariadb_prereq_pkgs

    {%- else %}
mariadb_pkg_{{ loop.index }}:
  pkg.installed:
    - pkgs:
      - {{ pkg }}: '{{ version }}*'
    - require:
      - pkg: mariadb_prereq_pkgs

    {%- endif %}
  {%- endfor %}

# Fix dir perms in case they are in mounted volumes
mariadb_log_dir:
  file.directory:
    - name: /var/log/mysql
    - user: mysql
    - group: adm
    - mode: 2750

mariadb_lib_dir:
  file.directory:
    - name: /var/lib/mysql
    - user: mysql
    - group: mysql
    - mode: 750

  {%- if grains["init"] == "systemd" %}
mariadb_systemd_override:
  file.managed:
    - name: /etc/systemd/system/mariadb.service.d/override.conf
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
      - file: /etc/systemd/system/mariadb.service.d/override.conf
    - watch_in:
      - service: mariadb_service
  {%- endif %}

mariadb_service:
  service.running:
    - name: mariadb
    - enable: True

mariadb_debian_conf:
  file.managed:
    - name: /etc/mysql/debian.cnf
    - user: root
    - group: root
    - mode: 0600
    - contents: |
        [client]
        host     = localhost
        user     = root
        password = {{ pillar["mariadb"]["root_password"] }}
        socket   = /run/mysqld/mysqld.sock
        [mysql_upgrade]
        host     = localhost
        user     = root
        password = {{ pillar["mariadb"]["root_password"] }}
        socket   = /run/mysqld/mysqld.sock

  {%- if not salt["file.file_exists"]("/root/.my.cnf") %}
mariadb_create_symlink_debian_sys_maint_to_root:
  file.symlink:
    - name: /root/.my.cnf
    - target: /etc/mysql/debian.cnf
  {%- endif %}

# We do not use salt mysql modules as they are very buggy
# MariaDB secure installation steps
mariadb_secure_root_password:
  cmd.run:
    - name: |
        mysql --socket=/run/mysqld/mysqld.sock -e "UPDATE mysql.global_priv SET priv=json_set(priv, '$.plugin', 'mysql_native_password', '$.authentication_string', PASSWORD('{{ pillar["mariadb"]["root_password"] }}')) WHERE User='root';"
    - require:
      - service: mariadb_service

mariadb_secure_remove_anonymous_users:
  cmd.run:
    - name: |
        mysql --socket=/run/mysqld/mysqld.sock -e "DELETE FROM mysql.global_priv WHERE User='';"
    - require:
      - service: mariadb_service

  {%- if "pmm_password" in pillar["mariadb"] %}
mariadb_pmm_sql_1:
  cmd.run:
    - name: |
        mysql -e "CREATE USER IF NOT EXISTS 'pmm'@'localhost';"
    - require:
      - service: mariadb_service

mariadb_pmm_sql_2:
  cmd.run:
    - name: |
        mysql -e "ALTER USER 'pmm'@'localhost' IDENTIFIED BY '{{ pillar["mariadb"]["pmm_password"] }}';"
    - require:
      - service: mariadb_service

mariadb_pmm_sql_3:
  cmd.run:
    - name: |
        mysql -e "GRANT SELECT, PROCESS, SUPER, REPLICATION CLIENT, RELOAD ON *.* TO 'pmm'@'localhost';"
    - require:
      - service: mariadb_service
  {%- endif %}

  {%- if "pmm_agent_setup" in pillar["mariadb"] and pillar["mariadb"]["pmm_agent_setup"] %}
mariadb_pmm_agent_repo:
  pkg.installed:
    - sources:
      - percona-release: 'https://repo.percona.com/apt/percona-release_latest.generic_all.deb'

mariadb_pmm_agent_enable_release:
  cmd.run:
    - name: percona-release enable pmm2-client release
    - unless: percona-release show | grep -q 'pmm2-client -'

mariadb_pmm_agent_pkg:
  pkg.installed:
    - refresh: True
    - pkgs:
      - pmm2-client
  {%- endif %}

mariadb_flush_privileges:
  cmd.run:
    - name: |
        mysql -e "FLUSH PRIVILEGES;"
    - require:
      - service: mariadb_service

{% endif %}
