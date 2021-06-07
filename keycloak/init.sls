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
  {%- for domain in pillar["keycloak"]["domains"] %}
            server {
                listen 443 ssl;
                server_name {{ domain["name"] }};
                access_log /var/log/nginx/{{ domain["name"] }}-access.log main;
                error_log /var/log/nginx/{{ domain["name"] }}-error.log;
                ssl_certificate /opt/acme/cert/keycloak_{{ domain["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/keycloak_{{ domain["name"] }}_key.key;
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

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["keycloak"]["domains"] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "openssl verify -CAfile /opt/acme/cert/keycloak_{{ domain["name"] }}_ca.cer /opt/acme/cert/keycloak_{{ domain["name"] }}_fullchain.cer 2>&1 | grep -q -i -e error -e cannot; [ ${PIPESTATUS[1]} -eq 0 ] && /opt/acme/home/acme_local.sh --cert-file /opt/acme/cert/keycloak_{{ domain["name"] }}_cert.cer --key-file /opt/acme/cert/keycloak_{{ domain["name"] }}_key.key --ca-file /opt/acme/cert/keycloak_{{ domain["name"] }}_ca.cer --fullchain-file /opt/acme/cert/keycloak_{{ domain["name"] }}_fullchain.cer --issue -d {{ domain["name"] }} || true"

keycloak_data_dir_{{ loop.index }}:
  file.directory:
    - name: /opt/keycloak/{{ domain["name"] }}/standalone
    - mode: 755
    - makedirs: True

keycloak_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["image"] }}

keycloak_container_{{ loop.index }}:
  docker_container.running:
    - name: keycloak-{{ domain["name"] }}
    - user: root
    - image: {{ domain["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:{{ domain["internal_port"] }}:8080/tcp
    - environment:
    {%- for var_key, var_val in domain["env_vars"].items() %}
        - {{ var_key }}: {{ var_val }}
    {%- endfor %}
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