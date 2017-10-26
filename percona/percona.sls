{% if (pillar['percona'] is defined) and (pillar['percona'] is not none) %}
  {%- if (pillar['percona']['enabled'] is defined) and (pillar['percona']['enabled'] is not none) and (pillar['percona']['enabled']) %}
percona_repo_deb:
  pkg.installed:
    - sources:
      - percona-release: 'salt://percona/files/percona-release_0.1-4.{{ grains['oscodename'] }}_all.deb'

    {%- if (pillar['percona']['version'] is defined) and (pillar['percona']['version'] is not none) %}
percona_client:
  pkg.installed:
    - name: percona-server-client-{{ pillar['percona']['version'] }}
    - refresh: True

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

percona_remove_default_database_test:
  mysql_database.absent:
    - name: test
    - connection_user: root
    - connection_pass: {{ pillar['percona']['root_password'] }}
    - require:
      - pkg: mysql_python_dep
      - service: percona_svc
      {%- endif %}

        {%- if (pillar['percona']['databases'] is defined) and (pillar['percona']['databases'] is not none) %}
          {%- for name in pillar['percona']['databases'] %}
mysql_database_{{ name }}:
  mysql_database.present:
    - name: {{ name }}
    - connection_user: root
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
    - host: {{ user['host'] }}
    - password: {{ user['password'] }}
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
    - host: {{ user['host'] }}
    - connection_user: root
    - connection_pass: {{ pillar['percona']['root_password'] }}
    - grant_option: {{ db['grant_option']|default(False) }}
    - require:
      - mysql_user: mysql_user_{{ name }}_{{ user['host'] }}
            {%- endfor %}
          {%- endfor %}
        {%- endif %}
      {%- endif %}
    {%- endif %}
  {%- endif %}
{% endif %}
