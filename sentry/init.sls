{% if pillar['sentry']['version'] is defined  %}
install_nginx:
  pkg.installed:
    - pkgs:
      - nginx-full

nginx_files_1:
  file.managed:
    - name: /etc/nginx/sites-available/{{ pillar["sentry"]["acme_domain"] }}.conf
    - contents: |
        set_real_ip_from 127.0.0.1;
        set_real_ip_from 172.16.0.0/16;
        real_ip_header X-Forwarded-For;
        real_ip_recursive on;
        server {
            listen 80;
            server_name {{ pillar["sentry"]["acme_domain"] }};
            location / {
                if ($request_method = GET) {
                  rewrite  ^ https://$host$request_uri? permanent;
                }
                return 405;
            }
        }
        server {
            listen 443 ssl;
            server_name {{ pillar["sentry"]["acme_domain"] }};
            ssl_certificate /opt/acme/cert/sentry_{{ pillar["sentry"]["acme_domain"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/sentry_{{ pillar["sentry"]["acme_domain"] }}_key.key;
            ssl_ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:ECDH+3DES:DH+3DES:RSA+AESGCM:RSA+AES:RSA+3DES:!aNULL:!MD5:!DSS;
            ssl_session_cache shared:SSL:128m;
            ssl_session_timeout 10m;
            proxy_redirect off;
            # keepalive + raven.js is a disaster
            keepalive_timeout 0;
            # use very aggressive timeouts
            proxy_read_timeout 5s;
            proxy_send_timeout 5s;
            send_timeout 5s;
            resolver_timeout 5s;
            client_body_timeout 5s;
            # buffer larger messages
            client_max_body_size 5m;
            client_body_buffer_size 100k;
            location / {
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-For $remote_addr;
                proxy_set_header Host $http_host;
                proxy_pass http://localhost:9000/;
                add_header Strict-Transport-Security "max-age=31536000";
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

nginx_files_3:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ pillar["sentry"]["acme_domain"] }}.conf
    - target: /etc/nginx/sites-available/{{ pillar["sentry"]["acme_domain"] }}.conf

nginx_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["sentry"]["acme_account"] }}/verify_and_issue.sh sentry {{ pillar["sentry"]["acme_domain"] }}"

sentry_installer_clone_fom_git:
  git.latest:
    - name: https://github.com/getsentry/self-hosted.git
    - target: /opt/sentry/
    - rev: {{ pillar ["sentry"]["version"] }}
    - force_reset: True

sentry_config_1:
  file.managed:
    - name: '/opt/sentry/sentry/config.yml'
    - mode: '0644'
    - source: 'salt://sentry/files/config.yml'
    - template: jinja

{# sentry.conf.py best doc is here: https://github.com/getsentry/sentry/blob/master/src/sentry/conf/server.py #}
sentry_config_2:
  file.managed:
    - name: '/opt/sentry/sentry/sentry.conf.py'
    - mode: '0644'
    - source: 'salt://sentry/files/sentry.conf.py'
    - template: jinja

sentry_install:
  cmd.run:
    - name: ./install.sh --no-user-prompt --skip-commit-check
    - shell: /bin/bash
    - cwd: /opt/sentry
    - onchanges:
      - file: /opt/sentry/sentry/config.yml
      - file: /opt/sentry/sentry/sentry.conf.py
      - git: https://github.com/getsentry/self-hosted.git

sentry_volume_backup_script:
  file.managed:
    - name: /opt/sentry/backup_volumes.sh
    - contents: |
        #!/bin/bash
        mkdir -p /opt/sentry/backup/volumes/
        docker-compose --file /opt/sentry/docker-compose.yml run --rm -T -e SENTRY_LOG_LEVEL=CRITICAL web export > /opt/sentry/sentry/backup.json
        docker-compose --file /opt/sentry/docker-compose.yml stop
        docker run --rm --volumes-from sentry-self-hosted-clickhouse-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-clickhouse-1.tar /var/lib/clickhouse /var/log/clickhouse-server
        docker run --rm --volumes-from sentry-self-hosted-web-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-web-1.tar /data
        docker run --rm --volumes-from sentry-self-hosted-kafka-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-kafka-1.tar /var/lib/kafka/data /etc/kafka/secrets /var/lib/kafka/log
        docker run --rm --volumes-from sentry-self-hosted-nginx-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-nginx-1.tar /var/cache/nginx
        docker run --rm --volumes-from sentry-self-hosted-postgres-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-postgres-1.tar /var/lib/postgresql/data
        docker run --rm --volumes-from sentry-self-hosted-redis-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-redis-1.tar /data
        docker run --rm --volumes-from sentry-self-hosted-smtp-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-smtp-1.tar /var/spool/exim4 /var/log/exim4
        docker run --rm --volumes-from sentry-self-hosted-symbolicator-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-symbolicator-1.tar /data
        docker run --rm --volumes-from sentry-self-hosted-zookeeper-1 -v /opt/sentry/backup/volumes/:/backup ubuntu tar cvf /backup/sentry-self-hosted-zookeeper-1.tar /var/lib/zookeeper/data  /var/lib/zookeeper/log
        docker-compose --file /opt/sentry/docker-compose.yml up -d
    - mode: 774

sentry_volume_restore_script:
  file.managed:
    - name: /opt/sentry/restore_volumes.sh
    - contents: |
        #!/bin/bash
        docker-compose --file /opt/sentry/docker-compose.yml stop
        docker run --rm --volumes-from sentry-self-hosted-clickhouse-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-clickhouse-1.tar"
        docker run --rm --volumes-from sentry-self-hosted-web-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-web-1.tar"
        docker run --rm --volumes-from sentry-self-hosted-kafka-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-kafka-1.tar"
        docker run --rm --volumes-from sentry-self-hosted-nginx-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-nginx-1.tar"
        docker run --rm --volumes-from sentry-self-hosted-postgres-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-postgres-1.tar"
        docker run --rm --volumes-from sentry-self-hosted-redis-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-redis-1.tar"
        docker run --rm --volumes-from sentry-self-hosted-smtp-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-smtp-1.tar"
        docker run --rm --volumes-from sentry-self-hosted-symbolicator-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-symbolicator-1.tar"
        docker run --rm --volumes-from sentry-self-hosted-zookeeper-1 -v /opt/sentry/backup/volumes/:/backup ubuntu bash -c "cd / && tar xvf /backup/sentry-self-hosted-zookeeper-1.tar"
        docker-compose --file /opt/sentry/docker-compose.yml up -d
    - mode: 774

  {% if pillar['sentry']['secret'] is not defined or pillar['sentry']['secret'] is none %}
sentry_secret_generation:
  cmd.run:
    - name: docker-compose run --rm web config generate-secret-key 2>/dev/null
    - shell: /bin/bash
    - cwd: /opt/sentry
  {% else %}
sentry_docker_compose_up:
  cmd.run:
    - shell: /bin/bash
    - cwd: /opt/sentry
    - name: docker-compose up -d

sentry_superuser:
  cmd.run:
    - name: docker exec sentry-self-hosted-postgres-1 bash -c "( echo \"select id from auth_user where email = '{{ pillar['sentry']['admin_email'] }}' and is_superuser is true\" | su -l postgres -c \"psql postgres\" | grep -q \"(0 rows)\" )" && docker exec sentry-self-hosted-web-1 bash -c "sentry createuser --email '{{ pillar['sentry']['admin_email'] }}' --password '{{ pillar['sentry']['admin_password'] }}' --superuser --no-input" || true
    - runas: 'root'

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
  {%- endif %}
{%- endif %}
