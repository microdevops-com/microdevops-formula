{% if pillar["sentry"] is defined and "version" in pillar["sentry"]  %}
sentry_acme_run:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["sentry"]["acme_account"] }}/verify_and_issue.sh sentry {{ pillar["sentry"]["acme_domain"] }}"

sentry_install_nginx:
  pkg.installed:
    - pkgs:
      - nginx-full

sentry_nginx_files_1:
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

sentry_nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

sentry_nginx_files_3:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ pillar["sentry"]["acme_domain"] }}.conf
    - target: /etc/nginx/sites-available/{{ pillar["sentry"]["acme_domain"] }}.conf

sentry_installer_clone_fom_git:
  git.latest:
    - name: https://github.com/getsentry/self-hosted.git
    - target: /opt/sentry/
    - rev: {{ pillar ["sentry"]["version"] }}
    - force_reset: True

sentry_config_1:
  file.managed:
    - name: /opt/sentry/sentry/config.yml
    - mode: 0644
    - source: salt://sentry/files/config.yml
    - template: jinja

# sentry.conf.py best doc is here: https://github.com/getsentry/sentry/blob/master/src/sentry/conf/server.py
sentry_config_2:
  file.managed:
    - name: /opt/sentry/sentry/sentry.conf.py
    - mode: 0644
    - source: salt://sentry/files/sentry.conf.py
    - template: jinja

sentry_create_env_custom:
  file.copy:
    - name: /opt/sentry/.env.custom
    - source: /opt/sentry/.env
    - force: true

  {%- if salt["file.file_exists"]("/opt/sentry/.env.custom") %}
sentry_custom_env:
  file.replace:
    - name: /opt/sentry/.env.custom
    - pattern: '^ *SENTRY_EVENT_RETENTION_DAYS=.*$'
    - repl: 'SENTRY_EVENT_RETENTION_DAYS={{ salt["pillar.get"]("sentry:config:general:options:system:event_retention_days", 90) }}'
    - append_if_not_found: True

  {%- endif %}

  {%- if "enhance_image_sh" in pillar["sentry"] %}
sentry_enhance-image_sh_create:
  file.managed:
    - name: /opt/sentry/sentry/enhance-image.sh
    - contents: {{ salt["pillar.get"]("sentry:enhance_image_sh") | yaml_encode }}
    - mode: 755

  {%- else %}
sentry_enhance-image_sh_del:
  file.absent:
    - name: /opt/sentry/sentry/enhance-image.sh

  {%- endif %}

sentry_install:
  cmd.run:
    # For versions older than 22.10.0
    # - name: ./install.sh --no-user-prompt --skip-commit-check
    - name: ./install.sh --skip-user-creation --skip-commit-check --no-report-self-hosted-issues
    - shell: /bin/bash
    - cwd: /opt/sentry
    - onchanges:
      - file: /opt/sentry/sentry/config.yml
      - file: /opt/sentry/sentry/sentry.conf.py
      - git: https://github.com/getsentry/self-hosted.git
    - require:
      - cmd: sentry_acme_run

sentry_backup_dir:
  file.directory:
    - name: /opt/sentry/backup

sentry_export_backup_script:
  file.managed:
    - name: /opt/sentry/backup_export.sh
    - contents: |
        #!/bin/bash
        docker-compose --file /opt/sentry/docker-compose.yml run --rm -T -e SENTRY_LOG_LEVEL=CRITICAL web export > /opt/sentry/backup/backup.json

sentry_volume_backup_script:
  file.managed:
    - name: /opt/sentry/backup_volumes.sh
    - contents: |
        #!/bin/bash
        mkdir -p /opt/sentry/backup/volumes/
        docker-compose --file /opt/sentry/docker-compose.yml run --rm -T -e SENTRY_LOG_LEVEL=CRITICAL web export > /opt/sentry/backup/backup.json
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

  {%- if pillar["sentry"]["secret"] is not defined or pillar["sentry"]["secret"] is none %}
sentry_secret_generation:
  cmd.run:
    - name: docker-compose run --rm web config generate-secret-key 2>/dev/null
    - shell: /bin/bash
    - cwd: /opt/sentry

sentry_notification:
  cmd.run:
    - name: echo "  !!! ADD THE GENERATED SECRET IN THE PREVIOUS STEP TO THE PILLAR AND RUN THE STATE AGAIN !!!"

  {%- else %}
sentry_docker_compose_up:
  cmd.run:
    - shell: /bin/bash
    - cwd: /opt/sentry
    - name: |
        [[ -f /opt/sentry/.env.custom ]] && docker-compose --env-file /opt/sentry/.env.custom up -d || docker-compose up -d
    - require:
      - cmd: sentry_acme_run

sentry_superuser:
  cmd.run:
    - name: docker exec sentry-self-hosted-postgres-1 bash -c "( echo \"select id from auth_user where email = '{{ pillar["sentry"]["admin_email"] }}' and is_superuser is true\" | su -l postgres -c \"psql postgres\" | grep -q \"(0 rows)\" )" && docker exec sentry-self-hosted-web-1 bash -c "sentry createuser --email '{{ pillar["sentry"]["admin_email"] }}' --password '{{ pillar["sentry"]["admin_password"] }}' --superuser --no-input" || true
    - runas: root
    - require:
      - cmd: sentry_acme_run

    {%- if "fix_admin_permissions" in pillar["sentry"] and salt["pillar.get"]("sentry:fix_admin_permissions", False) %}
sentry_fix_sentry_admin_permissions:
  cmd.run:
    - name: docker exec sentry-self-hosted-web-1 sentry permissions add -u "{{ pillar["sentry"]["admin_email"] }}" -p "users.admin"
    - require:
      - cmd: sentry_acme_run
    {%- endif %}

sentry_nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx reload

sentry_nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx reload
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6

  {%- endif %}
{%- endif %}
