{% if pillar['loki'] is defined and pillar['loki'] is not none %}
docker_install_1:
  file.directory:
    - name: /etc/docker
    - mode: 700

docker_install_2:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: |
        { "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }

docker_install_3:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/{{ grains['os']|lower }} {{ grains['oscodename'] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/{{ grains['os']|lower }}/gpg

docker_install_4:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs: 
        - docker-ce: '{{ pillar['loki']['docker-ce_version'] }}*'
        - python3-pip
                
docker_pip_install:
  pip.installed:
    - name: docker-py >= 1.10
    - reload_modules: True

docker_install_5:
  service.running:
    - name: docker

docker_install_6:
  cmd.run:
    - name: systemctl restart docker
    - onchanges:
        - file: /etc/docker/daemon.json

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx
      - apache2-utils

basic_auth:
  webutil.user_exists:
    - name: {{ pillar["loki"]["auth_basic"]["username"] }}
    - password: {{ pillar["loki"]["auth_basic"]["password"] }}
    - htpasswd_file: /etc/nginx/htpasswd

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
            map $http_upgrade $connection_upgrade {
                default upgrade;
                '' close;
            }
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
            server {
                listen 80;
                return 301 https://$host$request_uri;
            }
            server {
                listen 443 ssl;
                server_name {{ pillar["loki"]["name"] }};
                ssl_certificate /opt/acme/cert/loki_{{ pillar["loki"]["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/loki_{{ pillar["loki"]["name"] }}_key.key;
                auth_basic "Administrator’s Area";
                auth_basic_user_file /etc/nginx/htpasswd;
                location / {
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header X-Forwarded-For $remote_addr;
                    proxy_set_header Host $http_host;
                    proxy_set_header Upgrade websocket;
                    proxy_set_header Connection Upgrade;
                    proxy_pass http://localhost:{{ pillar["loki"]["port"] }}/;
                }
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

nginx_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["loki"]["acme_account"] }}/verify_and_issue.sh loki {{ pillar["loki"]["name"] }}"

loki_data_dir:
  file.directory:
    - names:
      - /opt/loki/{{ pillar['loki']['name'] }}/chunks
      - /opt/loki/{{ pillar['loki']['name'] }}/rules
      - /opt/loki/{{ pillar['loki']['name'] }}/rules-temp
      - /opt/loki/{{ pillar['loki']['name'] }}/boltdb-shipper-active
      - /opt/loki/{{ pillar['loki']['name'] }}/boltdb-shipper-cache
      - /opt/loki/{{ pillar['loki']['name'] }}/boltdb-shipper-compactor
      - /opt/loki/{{ pillar['loki']['name'] }}/wal
    - mode: 755
    - user: 0
    - group: 0
    - makedirs: True

loki_config:
  file.managed:
    - name: /opt/loki/{{ pillar['loki']['name'] }}/config.yaml
    - user: 0
    - group: 0
    - mode: 644
    - contents: |
        auth_enabled: false
        server:
          http_listen_port: {{ pillar['loki']['port'] }}
          grpc_listen_port: 9096
        ingester:
          wal:
            enabled: true
            dir: /tmp/loki/wal
          lifecycler:
            address: 127.0.0.1
            ring:
              kvstore:
                store: inmemory
              replication_factor: 1
            final_sleep: 0s
          chunk_idle_period: 1h       # Any chunk not receiving new logs in this time will be flushed
          max_chunk_age: 1h           # All chunks will be flushed when they hit this age, default is 1h
          chunk_target_size: 1048576  # Loki will attempt to build chunks up to 1.5MB, flushing first if chunk_idle_period or max_chunk_age is reached first
          chunk_retain_period: 30s    # Must be greater than index read cache TTL if using an index cache (Default index read cache TTL is 5m)
          max_transfer_retries: 0     # Chunk transfers disabled
        schema_config:
          configs:
            - from: 2020-10-24
              store: boltdb-shipper
              object_store: filesystem
              schema: v11
              index:
                prefix: index_
                period: 24h
        storage_config:
          boltdb_shipper:
            active_index_directory: /tmp/loki/boltdb-shipper-active
            cache_location: /tmp/loki/boltdb-shipper-cache
            cache_ttl: 24h         # Can be increased for faster performance over longer query periods, uses more disk space
            shared_store: filesystem
          filesystem:
            directory: /tmp/loki/chunks
        compactor:
          working_directory: /tmp/loki/boltdb-shipper-compactor
          shared_store: filesystem
        limits_config:
          reject_old_samples: true
          reject_old_samples_max_age: 168h
        chunk_store_config:
          max_look_back_period: 0s
        table_manager:
          retention_deletes_enabled: false
          retention_period: 0s
        ruler:
          storage:
            type: local
            local:
              directory: /tmp/loki/rules
          rule_path: /tmp/loki/rules-temp
          alertmanager_url: http://localhost:9093
          ring:
            kvstore:
              store: inmemory
          enable_api: true
 
loki_image:
  cmd.run:
    - name: docker pull {{ pillar['loki']['image'] }}

loki_container:
  docker_container.running:
    - name: loki-{{ pillar['loki']['name'] }}
    - user: root
    - image: {{ pillar['loki']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:{{ pillar['loki']['port'] }}:{{ pillar['loki']['port'] }}/tcp
    - binds:
        - /opt/loki/{{ pillar['loki']['name'] }}:/tmp/loki
    - watch:
        - /opt/loki/{{ pillar['loki']['name'] }}/config.yaml
    - command: -config.file=/tmp/loki/config.yaml

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
