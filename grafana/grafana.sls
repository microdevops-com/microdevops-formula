{% if pillar['grafana'] is defined and pillar['grafana'] is not none %}

  {% from "acme/macros.jinja" import verify_and_issue %}

  {%- if pillar["docker-ce"] is not defined %}
    {%- set docker_ce = {"version": pillar["grafana"]["docker-ce_version"],
                         "daemon_json": '{ "dns": ["1.1.1.1", "8.8.8.8", "8.8.4.4"], "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }'} %}
  {%- endif %}
  {%- include "docker-ce/docker-ce.sls" with context %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

{% if pillar["grafana"]["separated_nginx_config"] is defined and pillar["grafana"]["separated_nginx_config"] %}
nginx_files_1:
  file.managed:
    - name: /etc/nginx/sites-available/grafana.conf
    - contents: |
        server {
            listen 80;
            return 301 https://$host$request_uri;
        }
  {%- for domain in pillar['grafana']['domains'] %}
        server {
            listen 443 ssl;
            server_name {{ domain['name'] }};
            root /opt/grafana/{{ domain['name'] }};
            index index.html;
            ssl_certificate /opt/acme/cert/grafana_{{ domain['name'] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/grafana_{{ domain['name'] }}_key.key;
        {% if pillar["grafana"]["nginx_allowed_ips"] is defined %}
          {%- for name, ip in pillar["grafana"]["nginx_allowed_ips"].items() %}
            allow {{ip}}; # {{name}}
          {%- endfor %}
            deny all;
        {% endif %}
    {%- for instance in domain['instances'] %}
            location /{{ instance['name'] }}/ {
                proxy_connect_timeout       300;
                proxy_send_timeout          300;
                proxy_read_timeout          300;
                send_timeout                300;
                proxy_http_version 1.1;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-For $remote_addr;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "Upgrade";
                proxy_set_header Host $http_host;
                proxy_pass http://localhost:{{ instance['port'] }};
            }
    {%- endfor %}
          }
  {%- endfor %}
nginx_symlink_1:
  file.symlink:
    - name: /etc/nginx/sites-enabled/grafana.conf
    - target: /etc/nginx/sites-available/grafana.conf

{% else %}
nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        worker_processes 4;
        worker_rlimit_nofile 40000;
        events {
            worker_connections 8192;
        }
        http {
            map $http_upgrade $connection_upgrade {
                default upgrade;
                '' close;
            }
            server {
                listen 80;
                return 301 https://$host$request_uri;
            }
  {%- for domain in pillar['grafana']['domains'] %}
            server {
                listen 443 ssl;
                server_name {{ domain['name'] }};
                root /opt/grafana/{{ domain['name'] }};
                index index.html;
                ssl_certificate /opt/acme/cert/grafana_{{ domain['name'] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/grafana_{{ domain['name'] }}_key.key;
    {%- for instance in domain['instances'] %}
                location /{{ instance['name'] }}/ {
                    proxy_connect_timeout       300;
                    proxy_send_timeout          300;
                    proxy_read_timeout          300;
                    send_timeout                300;
                    proxy_http_version 1.1;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header X-Forwarded-For $remote_addr;
                    proxy_set_header Upgrade $http_upgrade;
                    proxy_set_header Connection "Upgrade";
                    proxy_set_header Host $http_host;
                    proxy_pass http://localhost:{{ instance['port'] }}/;
                }
    {%- endfor %}
            }
  {%- endfor %}
        }
{% endif %}
nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- if pillar["grafana"]["acme_configs"] is defined and pillar["grafana"]["acme_account"] is not defined %}
    {% for acme_config in pillar["grafana"]["acme_configs"] %}

      {{ verify_and_issue(acme_config["name"], "grafana", acme_config["domains"]) }}

    {%- endfor%}
  {%- endif %}

  {%- for domain in pillar['grafana']['domains'] %}
    {%- if pillar["grafana"]["acme_configs"] is not defined and pillar["grafana"]["acme_account"] is defined %}

      {{ verify_and_issue(acme_config["name"], "grafana", domain["name"]) }}

    {%- endif %}
   
    {%- set i_loop = loop %}
    {%- for instance in domain['instances'] %}
grafana_dirs_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - names:
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/provisioning
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/provisioning/dashboards
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/provisioning/datasources
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/provisioning/notifiers
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/provisioning/plugins
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/log
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/data
    - mode: 755
    - makedirs: True

grafana_config_{{ loop.index }}_{{ i_loop.index }}:
  file.managed:
    - name: /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/grafana.ini
    - user: root
    - group: root
    - mode: 644
    - contents: {{ instance['config'] | yaml_encode }}

      {%- if instance['ldap_toml'] is defined and instance['ldap_toml'] is not none %}
ldap_toml_{{ loop.index }}_{{ i_loop.index }}:
  file.managed:
    - name: /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/ldap.toml
    - user: root
    - group: root
    - mode: 644
    - contents: {{ instance['ldap_toml'] | yaml_encode }}
      {%- endif %}
      {%- if instance['datasources'] is defined and instance['datasources'] is not none %}
grafana_datasources_{{ loop.index }}_{{ i_loop.index }}:
  file.serialize:
    - name: /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/provisioning/datasources/datasources.yaml
    - user: root
    - group: root
    - mode: 644
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ instance['datasources'] }}
      {%- endif %}

      {%- if "image_renderer" in instance and instance["image_renderer"]["external"] %}
gf_image_renderer_pull_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: 'docker pull grafana/grafana-image-renderer:{{ instance["image_renderer"]["version"] }}'
gf_image_renderer_run_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: grafana_image_renderer-{{ domain["name"] }}-{{ instance["name"] }}
    - user: root
    - image: 'grafana/grafana-image-renderer:{{ instance["image_renderer"]["version"] }}'
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - {{ instance["image_renderer"]["port"] }}:8081/tcp
      {%- endif %}

grafana_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker pull {{ instance['image'] }}

grafana_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: grafana-{{ domain['name'] }}-{{ instance['name'] }}
    - user: root
    - image: {{ instance['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:{{ instance['port'] }}:3000/tcp
    - binds:
        - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc:/etc/grafana:rw
        - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/data:/var/lib/grafana:rw
        - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/log:/var/log/grafana:rw
    - watch:
        - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/grafana.ini
    - environment:
        - GF_SECURITY_ADMIN_PASSWORD: {{ instance['admin_password'] }}
      {%- if instance['install_plugins'] is defined and instance['install_plugins'] is not none %}
        - GF_INSTALL_PLUGINS: {{ instance['install_plugins'] }}
      {%- endif %}
      {%- if instance['docker_logging'] is defined and instance['docker_logging'] is not none %}
    - log_driver: {{ instance['docker_logging']['driver'] }}
    - log_opt: {{ instance['docker_logging']['options'] }}
      {%- endif %}
      {%- if "image_renderer" not in instance or not instance["image_renderer"]["external"] %}
install_grafana_image_render_components_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker exec -t grafana-{{ domain['name'] }}-{{ instance['name'] }} bash -c 'apt update && apt install libnss3 libgbm1 libappindicator3-1 libxshmfence-dev libasound2 -y'
      {%- endif %}
    {%- endfor %}
  {%- endfor %}

  {%- for domain in pillar['grafana']['domains'] %}
nginx_domain_index_{{ loop.index }}:
  file.managed:
    - name: /opt/grafana/{{ domain['name'] }}/index.html
    - contents: |
    {%- if 'default_instance' in domain %}
        <meta http-equiv="refresh" content="0; url='https://{{ domain['name'] }}/{{ domain['default_instance'] }}/login'" />
    {%- else %}
      {%- for instance in domain['instances'] %}
        <a href="{{ instance['name'] }}/">{{ instance['name'] }}</a><br>
      {%- endfor %}
    {%- endif %}
  {%- endfor %}

nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx restart

nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx restart
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6

{% endif %}
