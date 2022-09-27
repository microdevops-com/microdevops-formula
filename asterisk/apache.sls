{% if pillar["freepbx"] is defined %}
{% set host = pillar["freepbx"]["host"] %}
{% set user = pillar["asterisk"]["user"] %}
{% set group = pillar["asterisk"]["group"] %}
{% set certificate_name = salt['pillar.get']('asterisk:acme:certificate_name', 'asterisk') %}
delete_/var/www/html/index.html:
  file.absent:
    - name: /var/www/html/index.html


apache_site_conf:
  apache.configfile:
    - name: /etc/apache2/sites-available/{{ host }}.conf
    - config:
      - VirtualHost:
{%- if salt['file.file_exists']('/etc/asterisk/keys/' + certificate_name + '.crt') and salt['file.file_exists']('/etc/asterisk/keys/' + certificate_name + '.key') %}
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
{%- if salt['file.file_exists']('/etc/asterisk/keys/' + certificate_name + '.crt') and salt['file.file_exists']('/etc/asterisk/keys/' + certificate_name + '.key') %}
          SSLCertificateFile: /etc/asterisk/keys/integration/webserver.crt
          SSLCertificateKeyFile:   /etc/asterisk/keys/integration/webserver.key
          SSLCertificateChainFile: /etc/asterisk/keys/{{ certificate_name }}_ca.pem
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

a2enmod:
  cmd.run:
    - names:
      - "a2enmod rewrite"
      - "a2enmod ssl" 
    - shell: /bin/bash

restart_apache2:
  cmd.run:
    - shell: /bin/bash
    - names: 
      - "systemctl restart apache2"


{% endif %}