{% if pillar["asterisk"] is defined and pillar["freepbx"] is defined and "version" in pillar["asterisk"] %}
{% set host = pillar["freepbx"]["host"] %}
{% set user = pillar["asterisk"]["user"] %}
{% set group = pillar["asterisk"]["group"] %}


apache2:
  pkg.installed

freepbx_depencies_installed:
  pkg.installed:
    - pkgs:
      - mariadb-server
      - mariadb-client
      - sox
      - mpg123
      - lame
      - ffmpeg
      - sqlite3
      - git
      - unixodbc
      - dirmngr
      - odbc-mariadb
      - sngrep
      - nodejs
      - npm
      - libicu-dev
      - pkg-config
      - postfix

php_installed:
  pkg.installed:
    - pkgs:
      - libapache2-mod-php7.4
      - php7.4 
      - php-pear 
      - php7.4-cgi 
      - php7.4-common 
      - php7.4-curl 
      - php7.4-mbstring 
      - php7.4-gd 
      - php7.4-mysql 
      - php7.4-bcmath 
      - php7.4-zip 
      - php7.4-xml 
      - php7.4-imap 
      - php7.4-json 
      - php7.4-snmp


replaces_php_apache2_conf:
  file.replace:
    - names: 
      - /etc/php/7.4/apache2/php.ini:
        - pattern: ^(upload_max_filesize =)(.*)  
        - repl: '\1 120M'
      - /etc/php/7.4/cli/php.ini:
        - pattern: ^(memory_limit =)(.*)  
        - repl: '\1 1256M'      
      - /etc/php/7.4/cli/php.ini:
        - pattern: ^(upload_max_filesize =)(.*)  
        - repl: '\1 120M'
      - /etc/apache2/envvars:
        - pattern: ^(export APACHE_RUN_USER=)(.*) 
        - repl: '\1{{ user }}'
      - /etc/apache2/envvars:
        - pattern: ^(export APACHE_RUN_GROUP=)(.*) 
        - repl: '\1{{ group }}'
      - /etc/apache2/apache2.conf:
        - pattern: ^(.*)(AllowOverride)(.*) 
        - repl: '\1\2 All'
    - append_if_not_found: True
    - require:
      - pkg: apache2

apache2_Service:
  service.running:
    - name: apache2
    - enable: True
    - reload: True
    - require:
      - pkg: apache2

files:
  file.managed:
    - user: root
    - group: root
    - mode: '0644'
    - names:
      - /etc/odbcinst.ini:
        - mode: '0644'
        - source: salt://asterisk/files/odbcinst.ini
      - /etc/odbc.ini:
        - source: salt://asterisk/files/odbc.ini
        - mode: '0644'
      - /var/lib/asterisk/agi-bin/realtime_transfer.sh:
        - source: salt://asterisk/files/agi-bin/realtime_transfer.sh
        - mode: '0755'

{%- if not salt['file.file_exists']('/usr/sbin/fwconsole') %}
freepbx_source:
  archive.extracted:
    - name: /usr/src
    - source: http://mirror.freepbx.org/modules/packages/freepbx/freepbx-16.0-latest.tgz
    - skip_verify: True
    - keep_source: False

install_freepbx:
  cmd.run:
    - cwd: /usr/src/freepbx
    - shell: /bin/bash
    - names: 
      - "asterisk -x 'core stop now'"
      - "systemctl stop asterisk"
      - "./start_asterisk start > /dev/null 2>&1"
      - "./install -n"
      - "fwconsole chown"
      #- "fwconsole ma upgradeall"
{% endif %}


{% if pillar["freepbx"]["modules"] is defined %}
  {% for modul in pillar["freepbx"]["modules"] %}
    {%- if not salt['file.directory_exists']('/var/www/html/admin/modules/' + modul + '/') %}   
fwconsole ma downloadinstall {{ modul }}:
  cmd.run:
    - name: "fwconsole ma downloadinstall {{ modul }}"
    {%- endif %}
  {% endfor %}
{% endif %}

{% if pillar["freepbx"]["administrator"] is defined %}
administrator:
  cmd.run:
    - name: /usr/bin/mysql -uroot -e "REPLACE INTO ampusers SET username = '{{ pillar["freepbx"]["administrator"]["username"] }}', password_sha1 = SHA1('{{ pillar["freepbx"]["administrator"]["password"] }}'), sections = '*';" asterisk
{%- endif %}

{% if pillar["freepbx"]["Scheduler_and_Alerts"] is defined %}
  {% for key in pillar["freepbx"]["Scheduler_and_Alerts"] %}
  {% set val = pillar["freepbx"]["Scheduler_and_Alerts"][key] %}
Scheduler_and_Alerts_{{ key }}:
  cmd.run:
    - name: /usr/bin/mysql -uroot -e "REPLACE INTO kvstore_FreePBX SET val = '{{ val }}', \`key\` = '{{ key }}', id = 'updates';" asterisk
  {% endfor %}
{% endif %}

{% if pillar["freepbx"]["freepbx_settings"] is defined %}
  {% for settings_key in pillar["freepbx"]["freepbx_settings"] %}
  {% set settings_val = pillar["freepbx"]["freepbx_settings"][settings_key] %}
freepbx_settings_{{ settings_key }}:
  cmd.run:
    - name: /usr/bin/mysql -uroot -e "UPDATE freepbx_settings SET value = '{{ settings_val }}' WHERE keyword = '{{ settings_key }}'" asterisk
  {% endfor %}
{% endif %}


restart_fwconsole:
  cmd.run:
    - shell: /bin/bash
    - names: 
      - "fwconsole reload"

{%- endif %}
