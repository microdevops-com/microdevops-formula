{% if pillar["sentry"]["webhooks"]["telegram"] is defined  %}
install_nginx:
  pkg.installed:
    - pkgs:
      - nginx

nginx_files_1:
  file.managed:
    - name: /etc/nginx/sites-available/{{ pillar["sentry"]["webhooks"]["telegram"]["acme_domain"] }}.conf
    - contents: |
        server {
            listen 80;
            server_name {{ pillar["sentry"]["webhooks"]["telegram"]["acme_domain"] }};
            return 301 https://$host$request_uri;
        }
        server {
            listen 443 ssl;
            server_name {{ pillar["sentry"]["webhooks"]["telegram"]["acme_domain"] }};
            ssl_certificate /opt/acme/cert/sentry-telegram-webhook_{{ pillar["sentry"]["webhooks"]["telegram"]["acme_domain"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/sentry-telegram-webhook_{{ pillar["sentry"]["webhooks"]["telegram"]["acme_domain"] }}_key.key;
            proxy_redirect off;
            proxy_read_timeout 5s;
            proxy_send_timeout 5s;
            send_timeout 5s;
            resolver_timeout 5s;
            client_body_timeout 5s;
            client_max_body_size 5m;
            client_body_buffer_size 100k;
            location / {
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-For $remote_addr;
                proxy_set_header Host $http_host;
                proxy_pass http://localhost:{{ pillar["sentry"]["webhooks"]["telegram"]["local_port"] }}/;
                add_header Strict-Transport-Security "max-age=31536000";
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

nginx_files_3:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ pillar["sentry"]["webhooks"]["telegram"]["acme_domain"] }}.conf
    - target: /etc/nginx/sites-available/{{ pillar["sentry"]["webhooks"]["telegram"]["acme_domain"] }}.conf

nginx_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["sentry"]["webhooks"]["telegram"]["acme_account"] }}/verify_and_issue.sh sentry-telegram-webhook {{ pillar["sentry"]["webhooks"]["telegram"]["acme_domain"] }}"

sentry-telegram-webhook_clone_fom_git:
  git.latest:
    - name: {{ pillar["sentry"]["webhooks"]["telegram"]["repo"] }}
    - target: /opt/sentry-telegram-webhook
    - force_reset: True

docker_build_sentry-telegram-webhook:
  docker_image.present:
    - name:  {{ pillar["sentry"]["webhooks"]["telegram"]["image"] }}
    - build: /opt/sentry-telegram-webhook
    - tag: latest
    - force: True

sentry-telegram-webhook_container:
  docker_container.running:
    - name: {{ pillar["sentry"]["webhooks"]["telegram"]["container_name"] }}
    - user: root
    - image: {{ pillar["sentry"]["webhooks"]["telegram"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
       - '127.0.0.1:{{ pillar["sentry"]["webhooks"]["telegram"]["local_port"] }}:8000/tcp'
    - environment:
    {%- for var_key, var_val in pillar["sentry"]["webhooks"]["telegram"]["env_vars"].items() %}
        - {{ var_key }}: '{{ var_val }}'
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

{%- endif %}
