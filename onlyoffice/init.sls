{% if pillar["onlyoffice"] is defined %}
  {%- if pillar["docker-ce"] is not defined %}
    {%- set docker_ce = {"version": pillar["onlyoffice"]["docker-ce_version"],
                         "daemon_json": '{ "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }'} %}
  {%- endif %}
  {%- include "docker-ce/docker-ce.sls" with context %}

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
            map $http_host $this_host {
                "" $host;
                default $http_host;
            }
            map $http_x_forwarded_proto $the_scheme {
                 default $http_x_forwarded_proto;
                 "" $scheme;
            }
            map $http_x_forwarded_host $the_host {
                default $http_x_forwarded_host;
                "" $this_host;
            }
            map $http_upgrade $proxy_connection {
              default upgrade;
              "" close;
            }
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $proxy_connection;
            proxy_set_header X-Forwarded-Host $the_host;
            proxy_set_header X-Forwarded-Proto $the_scheme;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            server {
                listen 80;
                return 301 https://$host$request_uri;
                server_tokens off;
            }
  {%- for domain in pillar["onlyoffice"]["domains"] %}

            server {
                listen 443 ssl;
                server_name {{ domain["name"] }};
                server_tokens off;
                ssl_certificate /opt/acme/cert/onlyoffice_{{ domain["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/onlyoffice_{{ domain["name"] }}_key.key;
                ssl_verify_client off;
                ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
                ssl_protocols  TLSv1 TLSv1.1 TLSv1.2;
                ssl_session_cache  builtin:1000  shared:SSL:10m;
                ssl_prefer_server_ciphers   on;
                #add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
                #add_header X-Frame-Options SAMEORIGIN;
                #add_header X-Content-Type-Options nosniff;
                location / {
                    proxy_pass http://localhost:{{ domain["internal_port"] }}/;
                    proxy_http_version 1.1;
                }
            }
  {%- endfor %}
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["onlyoffice"]["domains"] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "openssl verify -CAfile /opt/acme/cert/onlyoffice_{{ domain["name"] }}_ca.cer /opt/acme/cert/onlyoffice_{{ domain["name"] }}_fullchain.cer 2>&1 | grep -q -i -e error -e cannot; [ ${PIPESTATUS[1]} -eq 0 ] && /opt/acme/home/acme_local.sh --cert-file /opt/acme/cert/onlyoffice_{{ domain["name"] }}_cert.cer --key-file /opt/acme/cert/onlyoffice_{{ domain["name"] }}_key.key --ca-file /opt/acme/cert/onlyoffice_{{ domain["name"] }}_ca.cer --fullchain-file /opt/acme/cert/onlyoffice_{{ domain["name"] }}_fullchain.cer --issue -d {{ domain["name"] }} || true"

create_onlyoffice_dirs_{{ loop.index }}:
  file.directory:
    - names:
      - /opt/onlyoffice/{{ domain["name"] }}/var/log/onlyoffice/
      - /opt/onlyoffice/{{ domain["name"] }}/var/www/onlyoffice/Data/
      - /opt/onlyoffice/{{ domain["name"] }}/var/lib/onlyoffice/
      - /opt/onlyoffice/{{ domain["name"] }}/var/lib/postgresql/
    - mode: 755
    - makedirs: True

onlyoffice_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["image"] }}

onlyoffice_container_{{ loop.index }}:
  docker_container.running:
    - name: onlyoffice-{{ domain["name"] }}
    - user: root
    - image: {{ domain["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - binds:
        - /opt/onlyoffice/{{ domain["name"] }}/var/log/onlyoffice:/var/log/onlyoffice:rw
        - /opt/onlyoffice/{{ domain["name"] }}/var/www/onlyoffice/Data:/var/www/onlyoffice/Data:rw
        - /opt/onlyoffice/{{ domain["name"] }}/var/lib/onlyoffice:/var/lib/onlyoffice:rw
        - /opt/onlyoffice/{{ domain["name"] }}/var/lib/postgresql:/var/lib/postgresql:rw
    - publish:
        - 127.0.0.1:{{ domain["internal_port"] }}:80/tcp
    - client_timeout: 120
    {%- if "env_vars" in domain %}
    - environment:
      {%- for var_key, var_val in domain["env_vars"].items() %}
        - {{ var_key }}: {{ var_val }}
      {%- endfor %}
    {%- endif %}

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
