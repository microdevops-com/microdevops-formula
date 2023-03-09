{% if pillar["sentry"] is defined and "webhooks" in pillar["sentry"] and "matrix" in pillar["sentry"]["webhooks"]  %}
install_nginx:
  pkg.installed:
    - pkgs:
      - nginx

nginx_files_1:
  file.managed:
    - name: /etc/nginx/sites-available/{{ pillar["sentry"]["webhooks"]["matrix"]["acme_domain"] }}.conf
    - contents: |
        server {
            listen 80;
            server_name {{ pillar["sentry"]["webhooks"]["matrix"]["acme_domain"] }};
            return 301 https://$host$request_uri;
        }
        server {
            listen 443 ssl;
            server_name {{ pillar["sentry"]["webhooks"]["matrix"]["acme_domain"] }};
            ssl_certificate /opt/acme/cert/sentry-matrix-webhook_{{ pillar["sentry"]["webhooks"]["matrix"]["acme_domain"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/sentry-matrix-webhook_{{ pillar["sentry"]["webhooks"]["matrix"]["acme_domain"] }}_key.key;
            proxy_redirect off;
            keepalive_timeout 0;
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
                proxy_pass http://localhost:{{ pillar["sentry"]["webhooks"]["matrix"]["env_vars"]["APP_PORT"] }}/;
                add_header Strict-Transport-Security "max-age=31536000";
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

nginx_files_3:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ pillar["sentry"]["webhooks"]["matrix"]["acme_domain"] }}.conf
    - target: /etc/nginx/sites-available/{{ pillar["sentry"]["webhooks"]["matrix"]["acme_domain"] }}.conf

nginx_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["sentry"]["webhooks"]["matrix"]["acme_account"] }}/verify_and_issue.sh sentry-matrix-webhook {{ pillar["sentry"]["webhooks"]["matrix"]["acme_domain"] }}"

  {% if pillar["sentry"]["webhooks"]["matrix"]["use_roman_k_fork"] is defined and pillar["sentry"]["webhooks"]["matrix"]["use_roman_k_fork"] %}
matrix-sentry-webhooks_clone_fom_git:
  git.latest:
    - name: {{ pillar["sentry"]["webhooks"]["matrix"]["repo"] }}
    - target: /opt/matrix-sentry-webhooks

bocker_build_matrix-sentry-webhooks:
  docker_image.present:
    - name:  {{ pillar["sentry"]["webhooks"]["matrix"]["image"] }}
    - build: /opt/matrix-sentry-webhooks
    - tag: latest
  {%- endif %}

matrix-sentry-webhooks_container:
  docker_container.running:
    - name: {{ pillar["sentry"]["webhooks"]["matrix"]["container_name"] }}
    - user: root
    - image: {{ pillar["sentry"]["webhooks"]["matrix"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
       - "127.0.0.1:{{ pillar["sentry"]["webhooks"]["matrix"]["env_vars"]["APP_PORT"] }}:{{ pillar["sentry"]["webhooks"]["matrix"]["env_vars"]["APP_PORT"] }}/tcp"
    - environment:
    {%- for var_key, var_val in pillar["sentry"]["webhooks"]["matrix"]["env_vars"].items() %}
        - {{ var_key }}: "{{ var_val }}"
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
