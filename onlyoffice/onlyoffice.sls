{% if pillar['onlyoffice'] is defined and pillar['onlyoffice'] is not none %}
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
        - docker-ce: '{{ pillar['onlyoffice']['docker-ce_version'] }}*'
        - python-pip
        - python3-pip

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
    - name: 'certbot --nginx certonly --keep-until-expiring --allow-subset-of-names --agree-tos --email {{ pillar['onlyoffice']['email'] }} -d {{ pillar['onlyoffice']['domain'] }}'

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
                server_name {{ pillar['onlyoffice']['domain'] }};
                ssl_certificate     /etc/letsencrypt/live/{{ pillar['onlyoffice']['domain'] }}/fullchain.pem;
                ssl_certificate_key /etc/letsencrypt/live/{{ pillar['onlyoffice']['domain'] }}/privkey.pem;

                location / {
                    proxy_pass http://localhost:{{ pillar['onlyoffice']['port'] }}/;
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

onlyoffice_running_container:
  docker_container.running:
    - name: onlyoffice_documentserver
    - user: root
    - image: {{ pillar['onlyoffice']['image'] }}
    - detach: True
    - restart_policy: always
    - publish:
        - {{ pillar['onlyoffice']['port'] }}:80/tcp
    - client_timeout: 120

{% endif %}
