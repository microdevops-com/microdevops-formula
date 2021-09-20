{% if pillar['metabase'] is defined and pillar['metabase'] is not none %}
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
        - docker-ce: '{{ pillar['metabase']['docker-ce_version'] }}*'
        - python-pip
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
            server {
                listen 80;
                return 301 https://$host$request_uri;
            }
  {%- for domain in pillar['metabase']['domains'] %}
            server {
                listen 443 ssl;
                server_name {{ domain['name'] }};
                root /opt/metabase/{{ domain['name'] }};
                index index.html;
                ssl_certificate /opt/acme/cert/metabase_{{ domain['name'] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/metabase_{{ domain['name'] }}_key.key;
    {%- for instance in domain['instances'] %}
                location /{{ instance['name'] }}/ {
                    proxy_pass http://localhost:{{ instance['port'] }}/;
                }
    {%- endfor %}
  {%- endfor %}
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar['metabase']['domains'] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["metabase"]["acme_account"] }}/verify_and_issue.sh metabase {{ domain['name'] }}"
    
    {%- set i_loop = loop %}
    {%- for instance in domain['instances'] %}
metabase_etc_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - name: /opt/metabase/{{ domain['name'] }}/{{ instance['name'] }}
    - mode: 755
    - makedirs: True

metabase_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker pull {{ instance['image'] }}

metabase_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: metabase-{{ domain['name'] }}-{{ instance['name'] }}
    - user: root
    - image: {{ instance['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:{{ instance['port'] }}:3000/tcp
    - environment:
        - MB_DB_TYPE: {{ instance['db']['type'] }}
        - MB_DB_HOST: {{ instance['db']['host'] }}
        - MB_DB_PORT: {{ instance['db']['port'] }}
        - MB_DB_DBNAME: {{ instance['db']['dbname'] }}
        - MB_DB_USER: {{ instance['db']['user'] }}
        - MB_DB_PASS: {{ instance['db']['pass'] }}
        - JAVA_TIMEZONE: {{ instance['java_timezone'] }}
        - MB_SITE_URL: https://{{ domain['name'] }}/{{ instance['name'] }}/

    {%- endfor %}
  {%- endfor %}

  {%- for domain in pillar['metabase']['domains'] %}
nginx_domain_index_{{ loop.index }}:
  file.managed:
    - name: /opt/metabase/{{ domain['name'] }}/index.html
    - contents: |
    {%- if 'default_instance' in domain %}
        <meta http-equiv="refresh" content="0; url='https://{{ domain['name'] }}/{{ domain['default_instance'] }}'" />
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
