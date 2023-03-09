{% if pillar["openresty"] is defined and grains["os"] in ["Ubuntu"]%}
{# https://openresty.org/en/linux-packages.html#ubuntu #}
openresty_requirements:
  pkg.installed:
    - pkgs:
      - wget
      - gnupg
      - ca-certificates 


openresty_gpgkey_download:
  cmd.run:
    - name: |
        wget -O /tmp/openresty.gpg https://openresty.org/package/pubkey.gpg 


openresty_gpgkey_add:
  cmd.run:
  {%- if grains["osmajorrelease"] <= 20 %}
    - name: cat /tmp/openresty.gpg | apt-key add -
  {%- elif grains["osmajorrelease"] >= 22 %}
    - name: gpg --batch --yes --no-tty --dearmor -o /usr/share/keyrings/openresty.gpg /tmp/openresty.gpg
  {%- endif %}


openresty_pkg_repo:
  file.managed:
    - name: /etc/apt/sources.list.d/openresty.list
    - contents: |
      {%- if grains["osarch"] in ["x86_64","amd64"] %}
      {%- set arch = "" %}
      {%- elif grains["osarch"] in ["arm64","aarch64"] %}
      {%- set arch = "/arm64" %}
      {%- endif %}

      {%- if grains["osmajorrelease"] <= 20 %}
        deb http://openresty.org/package{{ arch }}/ubuntu {{ grains["oscodename"] }} main
      {%- elif grains["osmajorrelease"] >= 22 %}
        deb [arch={{ grains["osarch"] }} signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package{{ arch }}/ubuntu {{ grains["oscodename"] }} main
      {%- endif %}
  

openresty_pkg_installed:
  pkg.installed:
    - pkgs:
      - openresty
    - refresh: True
    - allow_updates: True


  {%- set modules = [] %}
  {%- for module in pillar["openresty"].get("modules",[]) %}
    {%- do modules.extend(module["install"]) %}
    {%- set module_name = module["url"].split("/")[-1]|replace(".git","") %}
openresty_module_{{ module_name }}:
  git.latest:
    - name: {{ module["url"] }}
    - target: /usr/local/openresty/site/{{ module_name }}
    - force_reset: True
  {%- endfor %}

  
  {%- set parameters = {"sendfile": "on", "tcp_nopush": "on", "tcp_nodelay": "on", "keepalive_timeout": "65", "types_hash_max_size": "2048", "server_tokens": "off"} %}
  {%- do parameters.update(pillar["openresty"].get("parameters",{})) %}
openresty_config_managed:
  file.managed:
    - name: /etc/openresty/nginx.conf
    - source: salt://{{ pillar["openresty"]["configs"] }}/nginx.conf
    - template: jinja
    - defaults:
        modules: {{ modules }}
        parameters: {{ parameters }}


openresty_dir_logfiles:
  file.directory:
    - name: /var/log/openresty
    - user: root
    - group: root


openresty_dir_sites_available:
  file.directory:
    - name: /etc/openresty/sites-available
    - user: root
    - group: root
    - mode: 755


openresty_dir_sites_enabled:
  file.directory:
    - name: /etc/openresty/sites-enabled
    - user: root
    - group: root
    - mode: 755


openresty_link_nginx_compat:
  file.symlink:
    - name: /etc/nginx
    - target: /usr/local/openresty/nginx/conf
    - force: True
    - user: root
    - group: root


{% endif %}
