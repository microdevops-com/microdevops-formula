{% if (pillar['percona'] is defined) and (pillar['percona'] is not none) %}
  {%- if (pillar['percona']['enabled'] is defined) and (pillar['percona']['enabled'] is not none) and (pillar['percona']['enabled']) %}
percona_repo_deb:
  pkg.installed:
    - sources:
      - percona-release: 'salt://percona/files/percona-release_0.1-4.{{ grains['oscodename'] }}_all.deb'

    {%- if (pillar['percona']['version'] is defined) and (pillar['percona']['version'] is not none) %}
percona_client:
  pkg.installed:
    - refresh: True
    - pkgs:
        - libmysqlclient-dev
        - percona-server-client-{{ pillar['percona']['version'] }}

percona_config_dir:
  file.directory:
    - name: /etc/mysql/conf.d
    - makedirs: True
    - user: root
    - group: root

mysql_python_dep:
  pkg.installed:
    - name: python-mysqldb
    - reload_modules: True

percona_debconf_utils:
  pkg.installed:
    - name: debconf-utils

      {%- if (pillar['percona']['root_password'] is defined) and (pillar['percona']['root_password'] is not none) %}
percona_debconf:
  debconf.set:
    - name: percona-server-server-{{ pillar['percona']['version'] }}
    - data:
        'percona-server-server/root_password': {'type': 'password', 'value': '{{ pillar["percona"]["root_password"] }}'}
        'percona-server-server/root_password_again': {'type': 'password', 'value': '{{ pillar["percona"]["root_password"] }}'}
        'percona-server-server-{{ pillar['percona']['version'] }}/start_on_boot': {'type': 'boolean', 'value': 'true'}
    - require_in:
      - pkg: percona_server
    - require:
      - pkg: percona_debconf_utils

percona_server:
  pkg.installed:
    - name: percona-server-server-{{ pillar['percona']['version']  }}

percona_svc:
  service.running:
    - name: mysql
    - enable: True
    - require:
      - pkg: percona_server

        {%- if grains['init'] == 'systemd' %}
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
    - require_in:
      - pkg: percona_server
  module.run:
    - name: service.systemctl_reload
    - onchanges:
      - file: /etc/systemd/system/mysql.service.d/override.conf
    - watch_in:
      - service: percona_svc
        {%- endif %}

        {% if not salt['file.file_exists' ]('/root/.my.cnf') %}
percona_create_symlink_debian_sys_maint_to_root:
  file.symlink:
    - name: /root/.my.cnf
    - target: /etc/mysql/debian.cnf
        {% endif %}

        {%- if (pillar['percona']['secure_install'] is defined) and (pillar['percona']['secure_install'] is not none) and (pillar['percona']['secure_install']) %}
percona_disallow_root_remote_connection:
  mysql_query.run:
    - database: mysql
    - query: "DELETE FROM user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    - connection_user: root
    - connection_pass: {{ pillar['percona']['root_password'] }}
    - require:
      - pkg: mysql_python_dep
      - service: percona_svc

percona_remove_anonymous_user:
  mysql_query.run:
    - database: mysql
    - query: "DELETE FROM user WHERE User='';"
    - connection_user: root
    - connection_pass: {{ pillar['percona']['root_password'] }}
    - require:
      - pkg: mysql_python_dep
      - service: percona_svc

percona_remove_default_database_test:
  mysql_database.absent:
    - name: test
    - connection_user: root
    - connection_pass: {{ pillar['percona']['root_password'] }}
    - require:
      - pkg: mysql_python_dep
      - service: percona_svc

percona_delete_privileges_database_test:
  mysql_query.run:
    - database: mysql
    - query: "DELETE FROM db WHERE Db='test' OR Db='test\\_%'"
    - connection_user: root
    - connection_pass: {{ pillar['percona']['root_password'] }}
    - require:
      - pkg: mysql_python_dep
      - service: percona_svc
        {%- endif %}

        {%- if (pillar['percona']['databases'] is defined) and (pillar['percona']['databases'] is not none) %}
          {%- for db in pillar['percona']['databases'] %}
mysql_database_{{ db['name'] }}:
  mysql_database.present:
    - name: {{ db['name'] }}
    - connection_user: root
    - character_set: {{ db['character_set']|default('utf8mb4') }}
    - collate: {{ db['collate']|default('utf8mb4_unicode_ci') }}
    - connection_pass: {{ pillar['percona']['root_password'] }}
    - require:
      - pkg: mysql_python_dep
      - service: percona_svc
          {%- endfor %}
        {%- endif %}


        {%- if (pillar['percona']['users'] is defined) and (pillar['percona']['users'] is not none) %}
          {%- for name, user in pillar['percona']['users'].items() %}
mysql_user_{{ name }}_{{ user['host'] }}:
  mysql_user.present:
    - name: {{ name }}
    - host: '{{ user["host"] }}'
    - password: '{{ user["password"] }}'
    - connection_user: root
    - connection_pass: {{ pillar['percona']['root_password'] }}
    - require:
      - pkg: mysql_python_dep
      - service: percona_svc
            {%- for db in user['databases'] %}
mysql_grant_{{ name }}_{{ user['host'] }}_{{ loop.index0 }}:
  mysql_grants.present:
    - grant: '{{db['grant']|join(",")}}'
    - database: '{{ db['database'] }}.*'
    - user: {{ name }}
    - host: '{{ user["host"] }}'
    - connection_user: root
    - connection_pass: {{ pillar['percona']['root_password'] }}
    - grant_option: {{ db['grant_option']|default(False) }}
    - require:
      - mysql_user: mysql_user_{{ name }}_{{ user['host'] }}
            {%- endfor %}
          {%- endfor %}
        {%- endif %}

        {%- if ((pillar['percona']['version'] != '5.7') and (pillar['percona']['version'] != 5.7)) %}
percona_create_post_install_toolkit_functions:
    mysql_query.run:
    - database: mysql
    - query: "DROP FUNCTION IF EXISTS fnv1a_64; CREATE FUNCTION fnv1a_64 RETURNS INTEGER SONAME 'libfnv1a_udf.so'; DROP FUNCTION IF EXISTS fnv_64; CREATE FUNCTION fnv_64 RETURNS INTEGER SONAME 'libfnv_udf.so'; DROP FUNCTION IF EXISTS murmur_hash; CREATE FUNCTION murmur_hash RETURNS INTEGER SONAME 'libmurmur_udf.so'"
    - connection_user: root
    - connection_pass: {{ pillar['percona']['root_password'] }}
    - require:
      - pkg: mysql_python_dep
      - service: percona_svc
        {%- else %}
percona_debian_conf:
  file.managed:
    - name: '/etc/mysql/debian.cnf'
    - user: 'root'
    - group: 'root'
    - mode: '0600'
    - contents: |
        [client]
        host     = localhost
        user     = root
        password = {{ pillar['percona']['root_password'] }}
        socket   = /var/run/mysqld/mysqld.sock
        [mysql_upgrade]
        host     = localhost
        user     = root
        password = {{ pillar['percona']['root_password'] }}
        socket   = /var/run/mysqld/mysqld.sock
        basedir  = /usr
        {%- endif %}

      {%- endif %}
    {%- endif %}
  {%- endif %}
{% endif %}
