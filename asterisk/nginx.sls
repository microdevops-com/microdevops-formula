{% if pillar["asterisk"]["nginx"] is defined %}

nginx_deps:
  pkg.installed:
    - pkgs:
      - nginx


nginx_enable:
  service.running:
    - name: nginx
    - enable: True
    - require:
      - pkg: nginx_deps



{% if pillar["asterisk"]["nginx"]["htpasswd"] is defined %}
install_apache2_utils:
  pkg.installed:
    - name: apache2-utils

create_htpasswd:
  cmd.run:
    - name: '> /etc/nginx/.htpasswd'
    - require:
      - pkg: apache2-utils

  {% for user in pillar["asterisk"]["nginx"]["htpasswd"] %}
addend_htpasswd_{{ user["username"] }}:
  cmd.run:
    - name: |
        htpasswd -b /etc/nginx/.htpasswd {{ user["username"] }} {{ user["password"] }}
    - unless: grep -q "^{{ user["username"] }}:" /etc/nginx/.htpasswd
    - require:
      - pkg: apache2-utils    
  {% endfor %}
{% endif %}

nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - source: {{ pillar["asterisk"]["nginx"]["configs"] }}


nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

nginx_files_3:
  file.managed:
    - name: /etc/nginx/snippets/ssl-params.conf
    - contents: |
        # from https://cipherli.st/
        # and https://raymii.org/s/tutorials/Strong_SSL_Security_On_nginx.html
        
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
        ssl_ecdh_curve secp384r1;
        ssl_session_cache shared:SSL:10m;
        ssl_session_tickets off;
        ssl_stapling on;
        ssl_stapling_verify on;
        resolver 8.8.8.8 1.1.1.1 valid=300s;
        resolver_timeout 5s;
        
        ssl_dhparam /etc/ssl/certs/dhparam.pem;

nginx_files_4:
  file.managed:
    - mode: 664
    - user: www-data
    - group: www-data
    - template: jinja
    - names:
      {% for site in pillar["asterisk"]["nginx"]["sites"] %}
      - /etc/nginx/sites-available/{{ site.name }}:
        - source: {{ site.configs }}
        - context: {{ site.context }}
      {% endfor %}

{% for site in pillar["asterisk"]["nginx"]["sites"] %}
symlink:
  file.symlink:
    - names:
      - /etc/nginx/sites-enabled/{{ site.name }}:
        - target: /etc/nginx/sites-available/{{ site.name }}
{% endfor %}

nginx_dhparam:
  cmd.run:
    - name: '[ ! -f /etc/ssl/certs/dhparam.pem ] && openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 || /bin/true'
    - env:
      - RANDFILE: /root/.rnd


{% endif %}
