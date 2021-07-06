{% if pillar["mailcow"] is defined %}
docker_install_00:
  file.directory:
    - name: /etc/docker
    - mode: 700
docker_install_01:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: |
        { "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }
docker_install_02:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/{{ grains["os"]|lower }} {{ grains["oscodename"] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/{{ grains["os"]|lower }}/gpg
docker_install_03:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - docker-ce: "{{ pillar["mailcow"]["docker-ce_version"] }}*"
        - python3-pip
docker_pip_install:
  pip.installed:
    - name: docker-py >= 1.10
    - reload_modules: True
docker_install_3:
  service.running:
    - name: docker
docker_install_4:
  cmd.run:
    - name: systemctl restart docker
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
            use epoll;
            multi_accept on;
        }
        http {
            include /etc/nginx/mime.types;
            default_type application/octet-stream;
            sendfile on;
            tcp_nopush on;
            tcp_nodelay on;
            gzip on;
            gzip_comp_level 4;
            gzip_types text/plain text/css application/x-javascript text/xml application/xml application/xml+rss text/javascript;
            gzip_vary on;
            gzip_proxied any;
            client_max_body_size 1000m;
            log_format  main  '$remote_addr - [$time_local] "$host$request_uri" '
                              '$status $body_bytes_sent "$http_referer" '
                              '"$http_user_agent" "$proxy_add_x_forwarded_for"';
            server {
                listen 80;
                return 301 https://$host$request_uri;
            }
  {%- for domain in pillar["mailcow"]["domains"] %}
            server {
                listen 443 ssl;
                server_name {{ domain["name"] }};
                access_log /var/log/nginx/{{ domain["name"] }}-access.log main;
                error_log /var/log/nginx/{{ domain["name"] }}-error.log;
                ssl_certificate /opt/acme/cert/mailcow_{{ domain["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/mailcow_{{ domain["name"] }}_key.key;
                location / {
                    proxy_pass http://localhost:{{ domain["internal_port"] }};
                    include    proxy_params;
                    proxy_set_header    X-Real-IP          $remote_addr;
                    proxy_set_header    X-Forwarded-For    $proxy_add_x_forwarded_for;
                    proxy_set_header    X-Forwarded-Host   $host;
                    proxy_set_header    X-Forwarded-Proto  $scheme;
                    proxy_headers_hash_max_size 512;
                    proxy_headers_hash_bucket_size 128;
                }
            }
  {%- endfor %}
        }
nginx_files_2:                                                                                                                                                                                                                 [37/40190]
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["mailcow"]["domains"] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ domain["acme_account"] }}/verify_and_issue.sh mailcow {{ domain["name"] }}"

mailcow_clone_fom_git_{{ loop.index }}:
  git.cloned:
    - name: https://github.com/mailcow/mailcow-dockerized
    - target: /opt/mailcow/{{ domain["name"] }}

mailcow_config_http_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/generate_config.sh'
    - pattern: '^ *HTTP_PORT=.*$'
    - repl: 'HTTP_PORT={{ domain["internal_port"] }}'

mailcow_config_https_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/generate_config.sh'
    - pattern: '^ *HTTPS_PORT=.*$'
    - repl: 'HTTPS_PORT=8443'

mailcow_config_acme_off{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/generate_config.sh'
    - pattern: '^ *SKIP_LETS_ENCRYPT=.*$'
    - repl: 'SKIP_LETS_ENCRYPT=y'

mailcow_generate_config_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: if [[ ! -e /opt/mailcow/{{ domain["name"] }}/mailcow.conf ]]; then /opt/mailcow/{{ domain["name"] }}/generate_config.sh; fi
    - cwd: /opt/mailcow/{{ domain["name"] }}/
    - env:
      - MAILCOW_HOSTNAME: {{ domain["name"] }}
      - MAILCOW_TZ: Etc/UTC
mailcow_docker_compose_owerride_{{ loop.index }}:
  file.managed:
    - name: /opt/mailcow/{{ domain["name"] }}/docker-compose.override.yml
    - contents: |
        version: '2.1'
        services:
            mysql-mailcow:
              volumes:
                - ./volumes/mysql/var/lib/mysql/:/var/lib/mysql/:Z
            rspamd-mailcow:
              volumes:
                - ./volumes/var/lib/rspamd:/var/lib/rspamd:z
            dovecot-mailcow:
              volumes:
                - ./volumes/var/vmail:/var/vmail:Z
                - ./volumes/var/vmail_index:/var/vmail_index:Z
                - ./volumes/mail_crypt:/mail_crypt/:z
                - ./volumes/var/lib/rspamd:/var/lib/rspamd:z
            postfix-mailcow:
              volumes:
                - ./volumes/var/spool/postfix:/var/spool/postfix:z
                - ./volumes/var/lib/zeyple:/var/lib/zeyple:z
                - ./volumes/var/lib/rspamd:/var/lib/rspamd:z
            nginx-mailcow:
              volumes:
                - ./volumes/usr/lib/GNUstep/SOGo/:/usr/lib/GNUstep/SOGo/:z
            watchdog-mailcow:
              volumes:
                - ./volumes/var/lib/rspamd:/var/lib/rspamd:z
                - ./volumes/var/spool/postfix:/var/spool/postfix:z
            solr-mailcow:
              volumes:
                - ./volumes/opt/solr/server/solr/dovecot-fts/data:/opt/solr/server/solr/dovecot-fts/data:Z

mailcow_docker_compose_up_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - cwd: /opt/mailcow/{{ domain["name"] }}
    - name: cd /opt/mailcow/{{ domain["name"] }} && docker-compose up -d

  {%- endfor %}

nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx reload
nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx reload
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6
{% endif %}