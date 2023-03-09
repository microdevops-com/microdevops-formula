{% if pillar["percona"] is defined and pillar["percona"]["version"]|float >= 5.7 %}
percona_repo_deb:
  pkg.installed:
    - sources:
  {%- if grains["oscodename"] in ["focal", "jammy"] %}
      - percona-release: https://repo.percona.com/apt/percona-release_latest.generic_all.deb
  {%- else %}
      - percona-release: https://repo.percona.com/apt/percona-release_latest.{{ grains["oscodename"] }}_all.deb
  {%- endif %}

  {%- if pillar["percona"]["version"]|float >= 8.0 %}
percona_repo_8:
  cmd.run:
    - name: percona-release setup ps80
    - require:
      - pkg: percona_repo_deb
  {%- endif %}

percona_client:
  pkg.installed:
    - refresh: True
    - pkgs:
        - libmysqlclient-dev
  {%- if pillar["percona"]["version"]|float >= 8.0 %}
        - percona-server-client
  {%- else %}
        - percona-server-client-{{ pillar["percona"]["version"] }}
  {%- endif %}

percona_config_dir:
  file.directory:
    - name: /etc/mysql/conf.d
    - makedirs: True
    - user: root
    - group: root

mysql_python_dep:
  pkg.installed:
  {%- if grains["oscodename"] in ["focal", "jammy"] %}
    - name: python3-mysqldb
  {%- else %}
    - name: python-mysqldb
  {%- endif %}
    - reload_modules: True

percona_debconf_utils:
  pkg.installed:
    - name: debconf-utils

percona_debconf:
  debconf.set:
  {%- if pillar["percona"]["version"]|float >= 8.0 %}
    - name: percona-server-server
  {%- else %}
    - name: percona-server-server-{{ pillar["percona"]["version"] }}
  {%- endif %}
    - data:
        'percona-server-server/root_password': {'type': 'password', 'value': '{{ pillar["percona"]["root_password"] }}'}
        'percona-server-server/root_password_again': {'type': 'password', 'value': '{{ pillar["percona"]["root_password"] }}'}
  {%- if pillar["percona"]["version"]|float >= 8.0 %}
        'percona-server-server/start_on_boot': {'type': 'boolean', 'value': 'true'}
  {%- else %}
        'percona-server-server-{{ pillar["percona"]["version"] }}/start_on_boot': {'type': 'boolean', 'value': 'true'}
  {%- endif %}
    - require_in:
      - pkg: percona_server
    - require:
      - pkg: percona_debconf_utils

percona_server:
  pkg.installed:
  {%- if pillar["percona"]["version"]|float >= 8.0 %}
    - name: percona-server-server
  {%- else %}
    - name: percona-server-server-{{ pillar["percona"]["version"]  }}
  {%- endif %}

percona_svc:
  service.running:
    - name: mysql
    - enable: True
    - require:
      - pkg: percona_server

  {%- if grains["init"] == "systemd" %}
percona_remove_limits:
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
        ExecStartPre=/usr/bin/install -g mysql -o mysql -d /var/run/mysqld
    - require_in:
      - pkg: percona_server
  module.run:
    - name: service.systemctl_reload
    - onchanges:
      - file: /etc/systemd/system/mysql.service.d/override.conf
    - watch_in:
      - service: percona_svc
  {%- endif %}

percona_debian_conf:
  file.managed:
    - name: /etc/mysql/debian.cnf
    - user: root
    - group: root
    - mode: 0600
    - contents: |
        [client]
        host     = localhost
        user     = root
        password = {{ pillar["percona"]["root_password"] }}
        socket   = /var/run/mysqld/mysqld.sock
        [mysql_upgrade]
        host     = localhost
        user     = root
        password = {{ pillar["percona"]["root_password"] }}
        socket   = /var/run/mysqld/mysqld.sock

  {%- if not salt["file.file_exists"]('/root/.my.cnf') %}
percona_create_symlink_debian_sys_maint_to_root:
  file.symlink:
    - name: /root/.my.cnf
    - target: /etc/mysql/debian.cnf

  {%- endif %}

  {%- if "databases" in pillar["percona"] %}
    {%- for name, db in pillar["percona"]["databases"].items() %}
mysql_database_{{ loop.index }}:
  mysql_database.present:
    - name: {{ name }}
    - connection_user: root
    - character_set: {{ db["character_set"]|default('utf8mb4') }}
    - collate: {{ db["collate"]|default('utf8mb4_unicode_ci') }}
    - connection_pass: {{ pillar["percona"]["root_password"] }}
    - require:
      - pkg: mysql_python_dep
      - service: percona_svc

    {%- endfor %}
  {%- endif %}

  {%- if "users" in pillar["percona"] %}
    {%- for name, user in pillar["percona"]["users"].items() %}
mysql_user_{{ loop.index }}:
  mysql_user.present:
    - name: {{ name }}
    - host: '{{ user["host"] }}'
    - password: '{{ user["password"] }}'
    - connection_user: root
    - connection_pass: {{ pillar["percona"]["root_password"] }}
    - require:
      - pkg: mysql_python_dep
      - service: percona_svc

      {%- set i_loop = loop %}
      {%- for db in user["databases"] %}
mysql_grant_{{ i_loop.index }}_{{ loop.index }}:
  mysql_grants.present:
    - grant: '{{db["grant"]|join(",")}}'
        {%- if "unescape_db_name" in db %}
    - database: '{{ db["database"] }}.*'
        {%- else %}
    - database: '`{{ db["database"] }}`.*'
        {%- endif %}
    - escape: False
    - user: {{ name }}
    - host: '{{ user["host"] }}'
    - connection_user: root
    - connection_pass: {{ pillar["percona"]["root_password"] }}
    - grant_option: {{ db["grant_option"]|default(False) }}
    - require:
      - pkg: mysql_python_dep
      - service: percona_svc

      {%- endfor %}

    {%- endfor %}
  {%- endif %}
{% endif %}
