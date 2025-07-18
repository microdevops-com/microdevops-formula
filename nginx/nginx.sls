{% if pillar["nginx"] is defined %}

  {% if pillar["nginx"].get("ondrej_ppa", False) %}
   {% if grains["os"] == "Ubuntu" %}

nginx_ondrej_ppa_add:
  pkgrepo.managed:
    - name: deb https://ppa.launchpadcontent.net/ondrej/nginx/ubuntu {{ grains['oscodename'] }} main
    - dist: {{ grains['oscodename'] }}
    - file: /etc/apt/sources.list.d/ondrej-ubuntu-nginx-{{ grains['oscodename'] }}.list
    - keyserver: keyserver.ubuntu.com
    - keyid: E5267A6C
    - refresh: True

   {% elif grains["os"] == "Debian" %}

nginx_repo_add:
  pkgrepo.managed:
    - name: deb [signed-by=/etc/apt/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/debian {{ grains["oscodename"] }} nginx
    - file: /etc/apt/sources.list.d/nginx-debian.list
    - key_url: https://nginx.org/keys/nginx_signing.key
    - keyring: /etc/apt/keyrings/nginx-archive-keyring.gpg
    - aptkey: False
    - clean_file: True

   {% endif %}
  {% endif %}

nginx_deps:
  pkg.installed:
    - pkgs:
  {% if pillar["nginx"].get("custom_set", False) %}
      - nginx-{{ pillar["nginx"]["custom_set"] }}
  {% else %}
      - nginx
  {% endif %}

  {% if pillar["nginx"].get("enabled", True) %}
nginx_enable:
  service.running:
    - name: nginx
    - enable: True
    - require:
      - pkg: nginx_deps
  {% endif %}

nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - source: salt://{{ pillar["nginx"]["configs"] }}/nginx.conf

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

nginx_dhparam:
  cmd.run:
    - name: '[ ! -f /etc/ssl/certs/dhparam.pem ] && openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 || /bin/true'
    - env:
      - RANDFILE: /root/.rnd

  {%- set files = pillar["nginx"].get("files", {}) %}
  {%- if files is none %}
    {%- set files = {} %}
  {%- endif %}
  {%- set file_manager_defaults = {"default_user": "root", "default_group": "root"} %}
  {%- include "_include/file_manager/init.sls" with context %}

{% endif %}
