{% if pillar["asterisk"] is defined and "version" in pillar["asterisk"] %}
{% set version = pillar["asterisk"]["version"] %}
{% set user = pillar["asterisk"]["user"] %}
{% set group = pillar["asterisk"]["group"] %}


asterisk_depencies_installed:
  pkg.installed:
    - pkgs:
      - curl
      - libnewt-dev
      - libssl-dev
      - libncurses5-dev
      - subversion
      - libsqlite3-dev
      - build-essential
      - libjansson-dev
      - libxml2-dev
      - uuid-dev
      - libvpb1
      - sngrep
      - sox
      - ffmpeg
      - lame



asterisk_source:
  archive.extracted:
    - name: /usr/src
    - source: http://downloads.asterisk.org/pub/telephony/asterisk/old-releases/asterisk-{{ version }}.tar.gz
    - skip_verify: True
    - keep_source: False


{%- if not salt['file.file_exists']('/usr/src/asterisk-' + version + '/addons/mp3/mpg123.h') %}
install_get_mp3_source:
  cmd.run:
    - name: "./contrib/scripts/get_mp3_source.sh"
    - cwd: /usr/src/asterisk-{{ version }}
    - shell: /bin/bash
{% endif %}


run_configure:
  cmd.run:
    - names: 
      - "./contrib/scripts/install_prereq install"
      - "./configure"
    - cwd: '/usr/src/asterisk-{{ version }}'
    - shell: '/bin/bash'

{% if pillar["asterisk"]["modules"] %}
run_configure_modules:
  cmd.run:
    - names: 
      - "make menuselect.makeopts"
  {% for enableDisable in pillar["asterisk"]["modules"] %}
    {% for modul in pillar["asterisk"]["modules"][enableDisable] %}
      - 'menuselect/menuselect --{{ enableDisable }} {{ modul }} menuselect.makeopts'
    {% endfor %}
  {% endfor %}
    - cwd: '/usr/src/asterisk-{{ version }}'
    - shell: '/bin/bash'
{% endif %} 


run_make_and_install:
  cmd.run:
    - names: 
      - "make"
      - "make install"
{%- if not salt['file.directory_exists']('/etc/asterisk') and pillar["asterisk"]["make_samples"] is defined and pillar["asterisk"]["make_samples"] == True %}
      - "make samples"
{% endif %}
      - "make config"
      - "make install-logrotate"
      - "ldconfig"      
    - cwd: '/usr/src/asterisk-{{ version }}'
    - shell: '/bin/bash'


add_group_asterisk:
  group.present:
    - system: True
    - name: {{ group }}

add_user_asterisk:
  user.present:
    - name: {{ user }}
    - home: /var/lib/asterisk
    - groups:
      - audio
      - dialout
      - {{ group }}
    {% if salt['group.info']("docker") %}
      - docker
    {% endif %}


asterisk_dir_chmod:
  file.directory:
    - user: {{ user }}
    - group: {{ group }}
    - names:
      - /etc/asterisk
      - /var/lib/asterisk
      - /var/log/asterisk
      - /var/spool/asterisk
    - recurse:
      - user
      - group
      - mode


replace_/etc/default/asterisk:
  file.replace:
    - names: 
      - /etc/default/asterisk:
        - pattern: ^.*AST_USER=.*
        - repl: AST_USER="{{ user }}"
      - /etc/default/asterisk:
        - pattern: ^.*AST_GROUP=.*
        - repl: AST_GROUP="{{ group }}"    
    - append_if_not_found: True




{% if pillar["asterisk"]["state"] is defined %}
{%- for state_name, state_data in pillar["asterisk"]["state"].items() %}
{{state_name}}: {{ state_data }}
{%- endfor %}
{%- endif %}



{% if pillar["asterisk"] is defined and "configs_ini" in pillar["asterisk"] %}
{% set separator = salt['pillar.get']('asterisk:configs_ini:separator', ' = ') %}
{% macro macro_list(key, val) %}
        {%- if val | is_list %}
        {%- for item in val %}
        {{ key }}{{ separator }}{{ item }}
        {%- endfor %}
        {%- elif val is mapping %}

        {{ key }}
        {%- for item_key, item_val in val.items() %}
        {{- macro_list(item_key, item_val) }}
        {%- endfor %}
        {%- elif val is none and not val %}
        {{ key }}
        {%- else %}
        {{ key }}{{ separator }}{{ val }}
        {%- endif -%}
{% endmacro %}
{% macro macro_config_ini(config_ini_data, separator) %}
        {%- for section, section_data in config_ini_data.items() %}
        {{- macro_list(section, section_data) }}
        {%- endfor -%}
{% endmacro %}
  {%- for config_ini_name, config_ini_data in pillar["asterisk"]["configs_ini"].items() if not config_ini_name in ["dirs", "separator"] %}
asterisk_configs_ini_{{ loop.index }}:
  file.managed:
    - name: {{ config_ini_name }}
    - contents: |
        {{- macro_config_ini(config_ini_data) -}}

  {%- endfor %}
{% endif %}



service_asterisk_enable:
  service.running:
    - name: asterisk
    - enable: True


asterisk_core_reload:
  cmd.run:
    - shell: /bin/bash
    - names: 
      - "asterisk -x 'core reload'"


{% if pillar["asterisk"]["mysql"] is defined %}
mariadb_depencies_installed:
  pkg.installed:
    - pkgs:
      - mariadb-server
      - mariadb-client
      - odbc-mariadb
      - unixodbc

mysql-base:
  mysql_database.present:
    - names: {{ pillar["asterisk"]["mysql"]["database"] }}

  mysql_user.present:
    - name: {{ pillar["asterisk"]["mysql"]["user_db"] }}
    - password: {{ pillar["asterisk"]["mysql"]["pass_db"] }}

  {%- for databases_name in pillar["asterisk"]["mysql"]["database"] %}
mysql-grants-{{databases_name}}:
  mysql_grants.present:
    - grant: ALL PRIVILEGES
    - database: '{{databases_name}}.*' 
    - user: {{ pillar["asterisk"]["mysql"]["user_db"] }}
    - host: localhost
  {%- endfor %}


  {% if pillar["asterisk"]["mysql"]["run_sql"] is defined %}
run-mysql-sql:
  cmd.run:
    - names:
    {%- for run_sql in pillar["asterisk"]["mysql"]["run_sql"] %}
      - /usr/bin/mysql -h localhost < {{ run_sql }}
    {%- endfor %}      
    - shell: '/bin/bash'
  {%- endif %}
{%- endif %}




{%- endif %}
