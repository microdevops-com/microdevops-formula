{% if pillar["mailcow"] is defined %}
docker_install_00:
  file.directory:
    - name: /etc/docker
    - mode: 700
docker_install_01:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: |
        { "iptables": true, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }
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
postfix_stop_and_disable:
  service.dead:
    - name: postfix
      enable: False
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
                    proxy_pass http://localhost:{{ domain["HTTP_PORT"] }};
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
nginx_files_2:
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

mailcow_config_generator_http_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/generate_config.sh'
    - pattern: '^ *HTTP_PORT=.*$'
    - repl: 'HTTP_PORT={{ domain["HTTP_PORT"] }}'

mailcow_config_generator_http_bind_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/generate_config.sh'
    - pattern: '^ *HTTP_BIND=.*$'
    - repl: 'HTTP_BIND={{ domain["HTTP_BIND"] }}'

mailcow_config_generator_https_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/generate_config.sh'
    - pattern: '^ *HTTPS_PORT=.*$'
    - repl: 'HTTPS_PORT={{ domain["HTTPS_PORT"] }}'

mailcow_config_generator_https_bind_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/generate_config.sh'
    - pattern: '^ *HTTPS_BIND=.*$'
    - repl: 'HTTPS_BIND={{ domain["HTTPS_BIND"] }}'

mailcow_config_generator_smtp_local_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/generate_config.sh'
    - pattern: '^ *SMTP_PORT=.*$'
    - repl: 'SMTP_PORT={{ domain["SMTP_PORT"] }}'

mailcow_config_generator_smtps_local_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/generate_config.sh'
    - pattern: '^ *SMTPS_PORT=.*$'
    - repl: 'SMTPS_PORT={{ domain["SMTPS_PORT"] }}'

mailcow_config_generator_imap_local_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/generate_config.sh'
    - pattern: '^ *IMAP_PORT=.*$'
    - repl: 'IMAP_PORT={{ domain["IMAP_PORT"] }}'

mailcow_config_generator_imaps_local_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/generate_config.sh'
    - pattern: '^ *IMAPS_PORT=.*$'
    - repl: 'IMAPS_PORT={{ domain["IMAPS_PORT"] }}'

mailcow_config_generator_submission_local_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/generate_config.sh'
    - pattern: '^ *SUBMISSION_PORT=.*$'
    - repl: 'SUBMISSION_PORT={{ domain["SUBMISSION_PORT"] }}'

mailcow_generate_config_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: if [[ ! -e /opt/mailcow/{{ domain["name"] }}/mailcow.conf ]]; then /opt/mailcow/{{ domain["name"] }}/generate_config.sh; fi
    - cwd: /opt/mailcow/{{ domain["name"] }}/
    - env:
      - MAILCOW_HOSTNAME: {{ domain["name"] }}
      - MAILCOW_TZ: Etc/UTC

mailcow_config_http_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/mailcow.conf'
    - pattern: '^ *HTTP_PORT=.*$'
    - repl: 'HTTP_PORT={{ domain["HTTP_PORT"] }}'

mailcow_config_http_bind_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/mailcow.conf'
    - pattern: '^ *HTTP_BIND=.*$'
    - repl: 'HTTP_BIND={{ domain["HTTP_BIND"] }}'

mailcow_config_https_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/mailcow.conf'
    - pattern: '^ *HTTPS_PORT=.*$'
    - repl: 'HTTPS_PORT={{ domain["HTTPS_PORT"] }}'

mailcow_config_https_bind_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/mailcow.conf'
    - pattern: '^ *HTTPS_BIND=.*$'
    - repl: 'HTTPS_BIND={{ domain["HTTPS_BIND"] }}'

mailcow_config_smtp_local_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/mailcow.conf'
    - pattern: '^ *SMTP_PORT=.*$'
    - repl: 'SMTP_PORT={{ domain["SMTP_PORT"] }}'

mailcow_config_smtps_local_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/mailcow.conf'
    - pattern: '^ *SMTPS_PORT=.*$'
    - repl: 'SMTPS_PORT={{ domain["SMTPS_PORT"] }}'

mailcow_config_imap_local_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/mailcow.conf'
    - pattern: '^ *IMAP_PORT=.*$'
    - repl: 'IMAP_PORT={{ domain["IMAP_PORT"] }}'

mailcow_config_imaps_local_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/mailcow.conf'
    - pattern: '^ *IMAPS_PORT=.*$'
    - repl: 'IMAPS_PORT={{ domain["IMAPS_PORT"] }}'

mailcow_config_submission_local_port_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ domain["name"] }}/mailcow.conf'
    - pattern: '^ *SUBMISSION_PORT=.*$'
    - repl: 'SUBMISSION_PORT={{ domain["SUBMISSION_PORT"] }}'

mailcow_data_dir_1_{{ loop.index }}:
  file.directory:
    - name: /opt/mailcow/{{ domain["name"] }}/volumes/data
    - mode: 755
    - makedirs: True
mailcow_data_dir_2_{{ loop.index }}:
  file.directory:
    - name: /opt/mailcow/{{ domain["name"] }}/volumes/mail_crypt
    - mode: 755
    - makedirs: True
mailcow_data_dir_3_{{ loop.index }}:
  file.directory:
    - name: /opt/mailcow/{{ domain["name"] }}/volumes/opt/solr/server/solr/dovecot-fts/data
    - mode: 755
    - makedirs: True
mailcow_data_dir_4_{{ loop.index }}:
  file.directory:
    - name: /opt/mailcow/{{ domain["name"] }}/volumes/sogo_web
    - mode: 755
    - makedirs: True
mailcow_data_dir_5_{{ loop.index }}:
  file.directory:
    - name: /opt/mailcow/{{ domain["name"] }}/volumes/sogo_backup
    - mode: 755
    - makedirs: True
mailcow_data_dir_6_{{ loop.index }}:
  file.directory:
    - name: /opt/mailcow/{{ domain["name"] }}/volumes/var/vmail_index
    - mode: 755
    - makedirs: True
mailcow_data_dir_7_{{ loop.index }}:
  file.directory:
    - name: /opt/mailcow/{{ domain["name"] }}/volumes/var/vmail
    - mode: 755
    - makedirs: True
mailcow_data_dir_8_{{ loop.index }}:
  file.directory:
    - name: /opt/mailcow/{{ domain["name"] }}/volumes/var/lib/rspamd
    - mode: 755
    - makedirs: True
mailcow_data_dir_9_{{ loop.index }}:
  file.directory:
    - name: /opt/mailcow/{{ domain["name"] }}/volumes/var/lib/mysql
    - mode: 755
    - makedirs: True
mailcow_data_dir_10_{{ loop.index }}:
  file.directory:
    - name: /opt/mailcow/{{ domain["name"] }}/volumes/var/spool/postfix
    - mode: 755
    - makedirs: True
mailcow_data_dir_11_{{ loop.index }}:
  file.directory:
    - name: /opt/mailcow/{{ domain["name"] }}/volumes/var/run/mysqld
    - mode: 755
    - makedirs: True

mailcow_docker_compose_owerride_{{ loop.index }}:
  file.managed:
    - name: /opt/mailcow/{{ domain["name"] }}/docker-compose.override.yml
    - contents: |
        version: '2.1'
    {%- if "haproxy" in domain %}
        services:

            dovecot-mailcow:
              ports:
                - "${IMAP_PORT_HAPROXY:-127.0.0.1:10143}:10143"
                - "${IMAPS_PORT_HAPROXY:-127.0.0.1:10993}:10993"
                - "${POP_PORT_HAPROXY:-127.0.0.1:10110}:10110"
                - "${POPS_PORT_HAPROXY:-127.0.0.1:10995}:10995"
                - "${SIEVE_PORT_HAPROXY:-127.0.0.1:14190}:14190"

            postfix-mailcow:
              ports:
        #        - "${SMTP_PORT_HAPROXY:-127.0.0.1:10025}:10025"
                - "${SMTPS_PORT_HAPROXY:-127.0.0.1:10465}:10465"
                - "${SUBMISSION_PORT_HAPROXY:-127.0.0.1:10587}:10587"
                
    {%- endif %}
        volumes:
          vmail-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/vmail'
          vmail-index-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/vmail_index'
          mysql-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/lib/mysql'
          mysql-socket-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/run/mysqld'
          redis-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/data/'
          rspamd-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/lib/rspamd'
          solr-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/opt/solr/server/solr/dovecot-fts/data'
          postfix-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/spool/postfix'
          crypt-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/mail_crypt'
          sogo-web-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/sogo_web'
          sogo-userdata-backup-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/sogo_backup'

bind_ssl_certificate_for_services_in_docker_{{ loop.index }}:
  mount.mounted:
    - name: /opt/mailcow/{{ domain["name"] }}/data/assets/ssl/cert.pem
    - device: /opt/acme/cert/{{ domain["name"] }}/fullchain.cer
    - mkmnt: True
    - persist: True
    - fstype: none
    - opts: bind

bind_ssl_key_for_services_in_docker_{{ loop.index }}:
  mount.mounted:
    - name: /opt/mailcow/{{ domain["name"] }}/data/assets/ssl/key.pem
    - device: /opt/acme/cert/{{ domain["name"] }}/{{ domain["name"] }}.key
    - mkmnt: True
    - persist: True
    - fstype: none
    - opts: bind

create_script_rebind_ssl_for_services_in_docker_{{ loop.index }}:
  file.managed:
    - name: /opt/mailcow/{{ domain["name"] }}/rebind-ssl-for-services.sh
    - mode: 0744
    - contents: |
        #!/bin/bash
        umount /opt/mailcow/{{ domain["name"] }}/data/assets/ssl/cert.pem
        umount /opt/mailcow/{{ domain["name"] }}/data/assets/ssl/key.pem
        mount --bind /opt/acme/cert/{{ domain["name"] }}/fullchain.cer /opt/mailcow/{{ domain["name"] }}/data/assets/ssl/cert.pem
        mount --bind /opt/acme/cert/{{ domain["name"] }}/{{ domain["name"] }}.key /opt/mailcow/{{ domain["name"] }}/data/assets/ssl/key.pem
        cd /opt/mailcow/{{ domain["name"] }} && docker-compose restart

mailcow_docker_compose_up_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - cwd: /opt/mailcow/{{ domain["name"] }}
    - name: cd /opt/mailcow/{{ domain["name"] }} && docker-compose up -d

create_cron_rebind_ssl_for_services_in_docker_{{ loop.index }}:
  cron.present:
    - name: /opt/mailcow/{{ domain["name"] }}/rebind-ssl-for-services.sh
    - identifier: rebind_ssl_certificates_for_services_in_docker
    - user: root
    - minute: 0
    - hour: 4

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