{% if pillar['grafana'] is defined and pillar['grafana'] is not none %}
docker_install_00:
  file.directory:
    - name: /etc/docker
    - mode: 700

docker_install_01:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: |
        {"iptables": false}

docker_install_1:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/{{ grains['os']|lower }} {{ grains['oscodename'] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/{{ grains['os']|lower }}/gpg

docker_install_2:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs: 
        - docker-ce: '{{ pillar['grafana']['docker-ce_version'] }}*'
        - python3-pip
        # xenial has 1.9 package, it is not sufficiant for docker networks, so we need installing pip manually
        #- python-docker
                
docker_pip_install:
  pip.installed:
    - name: docker-py >= 1.10
    - reload_modules: True

docker_install_3:
  service.running:
    - name: docker

docker_install_4:
  cmd.run:
    - name: 'systemctl restart docker'
    - onchanges:
        - file: /etc/docker/daemon.json

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

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
  {%- endfor %}
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar['grafana']['domains'] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["grafana"]["acme_account"] }}/verify_and_issue.sh grafana {{ domain['name'] }} || true"
    
    {%- set i_loop = loop %}
    {%- for instance in domain['instances'] %}
grafana_etc_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - names:
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/provisioning
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/provisioning/dashboards
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/provisioning/datasources
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/provisioning/notifiers
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/provisioning/plugins
      - /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/log
    - mode: 755
    - makedirs: True

grafana_data_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - name: /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/data
    - mode: 755
    - makedirs: True

grafana_config_{{ loop.index }}_{{ i_loop.index }}:
  file.managed:
    - name: /opt/grafana/{{ domain['name'] }}/{{ instance['name'] }}/etc/grafana.ini
    - user: root
    - group: root
    - mode: 644
    - contents: {{ instance['config'] | yaml_encode }}

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

install_grafana_image_render_components_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker exec -t grafana-{{ domain['name'] }}-{{ instance['name'] }} bash -c 'apt update && apt install libnss3 libgbm1 libappindicator3-1 libxshmfence-dev libasound2 -y'
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
