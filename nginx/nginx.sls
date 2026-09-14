{% if pillar["nginx"] is defined %}

  {%- set nginx = pillar["nginx"] %}
  {%- set tls = nginx.get("tls", {}) %}
  {%- set ssl_protocols = tls.get("protocols", "TLSv1.2 TLSv1.3") %}
  {%- set ssl_ciphers = tls.get("ciphers", "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384") %}
  {%- set reverse_proxies = nginx.get("reverse_proxies", {}) %}

  {% if reverse_proxies.values() | selectattr("tls", "defined") | selectattr("tls.acme_account", "defined") | list %}
include:
  - acme
  {% endif %}

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

  {% if not ("configs_management_disabled" in pillar["nginx"] and pillar["nginx"]["configs_management_disabled"]) %}
nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - source: salt://{{ pillar["nginx"]["configs"] }}/nginx.conf
  {% if pillar["nginx"]["configs"] == "nginx/app_hosting" %}
    - template: jinja
  {% endif %}

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

nginx_files_3:
  file.managed:
    - name: /etc/nginx/snippets/ssl-params.conf
    - contents: |
        # from https://cipherli.st/
        # and https://raymii.org/s/tutorials/Strong_SSL_Security_On_nginx.html
        
        ssl_protocols {{ ssl_protocols }};
        ssl_prefer_server_ciphers on;
        ssl_ciphers {{ ssl_ciphers }};
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

  {% endif %}

  {%- set files = pillar["nginx"].get("files", {}) %}
  {%- if files is none %}
    {%- set files = {} %}
  {%- endif %}
  {%- set file_manager_defaults = {"default_user": "root", "default_group": "root"} %}
  {%- include "_include/file_manager/init.sls" with context %}

  {%- for vhost_name, vhost in reverse_proxies.items() %}
    {%- set vhost_tls = vhost.get("tls", {}) %}
    {%- set server_names = vhost.get("server_names", []) %}
    {%- if server_names is string %}
      {%- set server_names = [server_names] %}
    {%- endif %}
    {%- set acme_account = vhost_tls.get("acme_account") %}
    {%- set certificate_name = vhost_tls.get("certificate_name", vhost_name) %}
    {%- set certificate_domain = server_names[0] %}
    {%- set cert_file = vhost_tls.get("cert_file", "/opt/acme/cert/" ~ certificate_name ~ "_" ~ certificate_domain ~ "_fullchain.cer") %}
    {%- set key_file = vhost_tls.get("key_file", "/opt/acme/cert/" ~ certificate_name ~ "_" ~ certificate_domain ~ "_key.key") %}

    {%- if acme_account %}
nginx_reverse_proxy_{{ vhost_name }}_acme:
  cmd.run:
    - name: /opt/acme/home/{{ acme_account }}/verify_and_issue.sh {{ certificate_name }} {{ server_names | join(" ") }}
    - shell: /bin/bash
    - success_retcodes: [2]
    - require:
      - sls: acme
    {%- endif %}

nginx_reverse_proxy_{{ vhost_name }}_config:
  file.managed:
    - name: /etc/nginx/sites-available/{{ vhost_name }}.conf
    - source: salt://nginx/reverse_proxy_vhost.jinja
    - template: jinja
    - context:
        vhost: {{ vhost | json }}
        server_names: {{ server_names | json }}
        cert_file: {{ cert_file }}
        key_file: {{ key_file }}
    {%- if acme_account %}
    - require:
      - cmd: nginx_reverse_proxy_{{ vhost_name }}_acme
    {%- endif %}

nginx_reverse_proxy_{{ vhost_name }}_enabled:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ vhost_name }}.conf
    - target: /etc/nginx/sites-available/{{ vhost_name }}.conf
    - require:
      - file: nginx_reverse_proxy_{{ vhost_name }}_config

nginx_reverse_proxy_{{ vhost_name }}_reload:
  cmd.run:
    - name: /usr/sbin/nginx -t && /usr/sbin/nginx -s reload
    - onchanges:
    {%- if not nginx.get("configs_management_disabled", False) %}
      - file: nginx_files_1
      - file: nginx_files_3
    {%- endif %}
      - file: nginx_reverse_proxy_{{ vhost_name }}_config
      - file: nginx_reverse_proxy_{{ vhost_name }}_enabled
    {%- if acme_account %}
    - require:
      - cmd: nginx_reverse_proxy_{{ vhost_name }}_acme
    {%- endif %}
  {%- endfor %}

{% endif %}
