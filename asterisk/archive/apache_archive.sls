{% if pillar["asterisk_archive"] is defined and "host" in pillar["asterisk_archive"] %}
{% set host = pillar["asterisk_archive"]["host"] %}
{% set user = pillar["asterisk_archive"]["user"] %}
{% set group = pillar["asterisk_archive"]["group"] %}
{% set Auth_user = pillar["asterisk_archive"]["Auth_user"] %}
{% set Auth_passwd = pillar["asterisk_archive"]["Auth_passwd"] %}


apache2:
  pkg.installed

add_passwd_/etc/apache2/.htpasswd:
  webutil.user_exists:
    - name: {{ Auth_user }}
    - password: {{ Auth_passwd }}
    - htpasswd_file: /etc/apache2/.htpasswd
    - options: d
    - force: true

replaces_apache2_conf:
  file.replace:
    - names: 
      - /etc/apache2/apache2.conf:
        - pattern: ^(.*)(AllowOverride)(.*) 
        - repl: '\1\2 All'
    - append_if_not_found: True
    - require:
      - pkg: apache2

delete_/var/www/html/index.html:
  file.absent:
    - name: /var/www/html/index.html

apache_site_conf:
  apache.configfile:
    - name: /etc/apache2/sites-available/{{ host }}.conf
    - config:
      - VirtualHost:
{%- if salt['file.file_exists']('/opt/acme/cert/asterisk_' + host + '_cert.cer') and salt['file.file_exists']('/opt/acme/cert/asterisk_' + host + '_key.key') %}
          this: '*:443'
{%- else %}
          this: '*:80'
{%- endif %}
          ServerName:
            - {{ host }}
          ServerAlias:
            - www.{{ host }}
          DocumentRoot: "/var/www/html"
          ErrorLog: "${APACHE_LOG_DIR}/error.log"
          CustomLog: "${APACHE_LOG_DIR}/access.log combined"
          Alias: /archive/ "/var/archive/"
          Directory:
            this: /var/archive/
            Options: Indexes MultiViews
            AllowOverride: None
            AuthType: Basic
            AuthName: '"Restricted Content"'
            AuthUserFile: /etc/apache2/.htpasswd
            Require: valid-user
            files:
              this: '"\.(wav|mp3)$"'
              Forcetype: application/forcedownload
{%- if salt['file.file_exists']('/opt/acme/cert/asterisk_' + host + '_cert.cer') and salt['file.file_exists']('/opt/acme/cert/asterisk_' + host + '_key.key') %}
          SSLCertificateFile: /opt/acme/cert/asterisk_{{ host }}_cert.cer
          SSLCertificateKeyFile:   /opt/acme/cert/asterisk_{{ host }}_key.key
          SSLCertificateChainFile: /opt/acme/cert/asterisk_{{ host }}_fullchain.cer
      - VirtualHost:
          this: '*:80'
          ServerName:
            - {{ host }}
          Redirect: '"/" "https://{{ host }}/"'
{%- endif %}

disabled_000-default:
  apache_site.disabled:
    - name: 000-default
    - require:
      - pkg: apache2

site_enabled:
  apache_site.enabled:
    - name: {{ host }}
    - require:
      - pkg: apache2

apache2_Service:
  service.running:
    - name: apache2
    - enable: True
    - reload: True
    - require:
      - pkg: apache2

a2enmod:
  cmd.run:
    - names:
      - "a2enmod rewrite"
      - "a2enmod ssl" 
    - shell: /bin/bash

files:
  file.managed:
    - user: www-data
    - group: www-data
    - names:
      - /var/www/html/favicon.ico:
        - mode: '755'
        - source: salt://asterisk/files/favicon.ico

restart_apache2_fwconsole:
  cmd.run:
    - shell: /bin/bash
    - names: 
      - "systemctl restart apache2"
{%- endif %}
