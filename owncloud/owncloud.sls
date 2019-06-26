{% if pillar['owncloud'] is defined and pillar['owncloud'] is not none %}
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
        - docker-ce: '{{ pillar['owncloud']['docker-ce_version'] }}*'
        - python-pip
        - python3-pip # In the case of a salt work on a python3

docker_install_3:
  pip.installed:
    - name: docker
    - reload_modules: True
        
docker_start:
  service.running:
    - name: docker
        
nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

certbot_install_1:
  pkgrepo.managed:
    - name: deb http://ppa.launchpad.net/certbot/certbot/ubuntu {{ grains['oscodename'] }} main
    - dist: {{ grains['oscodename'] }}
    - file: /etc/apt/sources.list.d/certbot-ubuntu-certbot-{{ grains['oscodename'] }}.list
    - keyserver: keyserver.ubuntu.com
    - keyid: 75BCA694
    - refresh: True

certbot_install_2:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs: 
        - certbot
        - python-certbot-nginx

certificates_install:
  cmd.run:
    - name: 'certbot --nginx certonly --keep-until-expiring --allow-subset-of-names --agree-tos --email {{ pillar['owncloud']['certbot_email'] }} -d {{ pillar['owncloud']['domain'] }}'

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
            server {
                listen 443 ssl;
                server_name {{ pillar['owncloud']['domain'] }};
                ssl_certificate     /etc/letsencrypt/live/{{ pillar['owncloud']['domain'] }}/fullchain.pem;
                ssl_certificate_key /etc/letsencrypt/live/{{ pillar['owncloud']['domain'] }}/privkey.pem;

                client_max_body_size 513m;
    
                location / {
                    proxy_pass http://localhost:{{ pillar['owncloud']['port'] }}/;
                    include    proxy_params;
                }
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

nginx_reload:
  cmd.run:
    - name: systemctl reload nginx.service

owncload_bind_directory_create:
  file.directory:
    - name: {{ pillar['owncloud']['bind_directory'] }}
    - user: root
    - group: root
    - mode: 700
    - makedirs: True

docker_container_run_owncloud_redis:
  docker_container.running:
    - name: redis
    - user: root
    - environment:
      - REDIS_DATABASES: 1
    - binds:
      - /opt/owncloud/redis:/var/lib/redis
    - image: {{ pillar['owncloud']['redis_image'] }}
    - detach: True
    - restart_policy: always

docker_container_run_owncloud_mysql:
  docker_container.running:
    - name: mariadb
    - user: root
    - environment:
      - MARIADB_ROOT_PASSWORD: {{ pillar['owncloud']['mysql_root_password'] }}
      - MARIADB_USERNAME: owncloud
      - MARIADB_PASSWORD: {{ pillar['owncloud']['mysql_owncloud_password'] }}
      - MARIADB_DATABASE: owncloud
    - binds:
      - /opt/owncloud/mysql:/var/lib/mysql
      - /opt/owncloud/backup:/var/lib/backup
    - image: {{ pillar['owncloud']['mysql_image'] }}
    - detach: True
    - restart_policy: always

docker_container_run_owncloud_files:
  docker_container.running:
    - name: owncloud
    - user: root
    - environment:
      - OWNCLOUD_DOMAIN: localhost
      - OWNCLOUD_DB_TYPE: mysql
      - OWNCLOUD_DB_NAME: owncloud
      - OWNCLOUD_DB_USERNAME: owncloud
      - OWNCLOUD_DB_PASSWORD: {{ pillar['owncloud']['mysql_owncloud_password'] }}
      - OWNCLOUD_DB_HOST: db
      - OWNCLOUD_ADMIN_USERNAME: admin
      - OWNCLOUD_ADMIN_PASSWORD: {{ pillar['owncloud']['admin_password'] }}
      - OWNCLOUD_REDIS_ENABLED: true
      - OWNCLOUD_REDIS_HOST: redis
    - links: 
      - mariadb: db
      - redis: redis
    - publish:
        - {{ pillar['owncloud']['port'] }}:8080/tcp
    - binds:
      - /opt/owncloud/data:/mnt/data
    - image: {{ pillar['owncloud']['files_image'] }}
    - detach: True
    - restart_policy: always

{% endif %}
