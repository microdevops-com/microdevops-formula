{% if pillar["nextcloud-aio"] is defined and pillar["acme"] is defined and pillar["docker-ce"] is defined %}

  {% from "acme/macros.jinja" import verify_and_issue %}

  {% set acme = pillar["acme"].keys() | first %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

  {%- if pillar["nextcloud-aio"]["nginx_sites_enabled"] | default(false) %}
create nginx.conf:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        #user www-data;
        worker_processes auto;
        worker_rlimit_nofile 40000;
        pid /run/nginx.pid;
        include /etc/nginx/modules-enabled/*.conf;
        events {
            worker_connections 8192;
        }
        http {
          sendfile on;
          tcp_nopush on;
          tcp_nodelay on;
          keepalive_timeout 65;
          types_hash_max_size 2048;
          server_names_hash_bucket_size 64;
          include /etc/nginx/mime.types;
          default_type application/octet-stream;
          ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
          ssl_prefer_server_ciphers on;
          access_log /var/log/nginx/access.log;
          error_log /var/log/nginx/error.log;
          gzip on;
          include /etc/nginx/conf.d/*.conf;
          include /etc/nginx/sites-enabled/*;
        }

create /etc/nginx/sites-available/{{ pillar["nextcloud-aio"]["domain"] }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ pillar["nextcloud-aio"]["domain"] }}.conf
    - contents: |
        map $http_upgrade $connection_upgrade {
            default upgrade;
            '' close;
        }

        server {
            listen 80;
            #listen [::]:80;            # comment to disable IPv6

            if ($scheme = "http") {
                return 301 https://$host$request_uri;
            }
            if ($http_x_forwarded_proto = "http") {
                return 301 https://$host$request_uri;
            }

            listen 443 ssl http2;      # for nginx versions below v1.25.1
            #listen [::]:443 ssl http2; # for nginx versions below v1.25.1 - comment to disable IPv6

            # listen 443 ssl;      # for nginx v1.25.1+
            # listen [::]:443 ssl; # for nginx v1.25.1+ - keep comment to disable IPv6
            # http2 on;            # uncomment to enable HTTP/2 - supported on nginx v1.25.1+

            # listen 443 quic reuseport;       # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+ - please remove "reuseport" if there is already another quic listener on port 443 with enabled reuseport
            # listen [::]:443 quic reuseport;  # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+ - please remove "reuseport" if there is already another quic listener on port 443 with enabled reuseport - keep comment to disable IPv6
            # http3 on;                                 # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+
            # quic_gso on;                              # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+
            # quic_retry on;                            # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+
            # quic_bpf on;                              # improves  HTTP/3 / QUIC - supported on nginx v1.25.0+, if nginx runs as a docker container you need to give it privileged permission to use this option
            # add_header Alt-Svc 'h3=":443"; ma=86400'; # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+

            proxy_buffering off;
            proxy_request_buffering off;

            client_max_body_size 0;
            client_body_buffer_size 512k;
            # http3_stream_buffer_size 512k; # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+
            proxy_read_timeout 86400s;

            server_name {{ pillar["nextcloud-aio"]["domain"] }};

            location / {
                proxy_pass http://127.0.0.1:11000$request_uri; # Adjust to match APACHE_PORT and APACHE_IP_BINDING. See https://github.com/nextcloud/all-in-one/blob/main/reverse-proxy.md#adapting-the-sample-web-server-configurations-below

                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Port $server_port;
                proxy_set_header X-Forwarded-Scheme $scheme;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header Host $host;
                proxy_set_header Early-Data $ssl_early_data;

                # Websocket
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection $connection_upgrade;
            }

            # If running nginx on a subdomain (eg. nextcloud.example.com) of a domain that already has an wildcard ssl certificate from certbot on this machine,
            # the {{ pillar["nextcloud-aio"]["domain"] }} in the below lines should be replaced with just the domain (eg. example.com), not the subdomain.
            # In this case the subdomain should already be secured without additional actions
            ssl_certificate /opt/acme/cert/nextcloud-aio_{{ pillar["nextcloud-aio"]["domain"] }}_fullchain.cer;   # managed by certbot on host machine
            ssl_certificate_key /opt/acme/cert/nextcloud-aio_{{ pillar["nextcloud-aio"]["domain"] }}_key.key; # managed by certbot on host machine

            ssl_dhparam /etc/dhparam; # curl -L https://ssl-config.mozilla.org/ffdhe2048.txt -o /etc/dhparam

            ssl_early_data on;
            ssl_session_timeout 1d;
            ssl_session_cache shared:SSL:10m;

            ssl_protocols TLSv1.2 TLSv1.3;
            ssl_ecdh_curve x25519:x448:secp521r1:secp384r1:secp256r1;

            ssl_prefer_server_ciphers on;
            #ssl_conf_command Options PrioritizeChaCha;
            ssl_ciphers TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-GCM-SHA256;
        }

create symlink /etc/nginx/sites-enabled/{{ pillar["nextcloud-aio"]["domain"] }}.conf:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ pillar["nextcloud-aio"]["domain"] }}.conf
    - target: /etc/nginx/sites-available/{{ pillar["nextcloud-aio"]["domain"] }}.conf
    - force: True

delete /etc/nginx/sites-enabled/default:
  file.absent:
    - name: /etc/nginx/sites-enabled/default
  
  {%- else %}

nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        #user www-data;
        worker_processes auto;
        worker_rlimit_nofile 40000;
        pid /run/nginx.pid;
        include /etc/nginx/modules-enabled/*.conf;
        events {
            worker_connections 8192;
        }
        http {
          sendfile on;
          tcp_nopush on;
          tcp_nodelay on;
          keepalive_timeout 65;
          types_hash_max_size 2048;
          server_names_hash_bucket_size 64;
          include /etc/nginx/mime.types;
          default_type application/octet-stream;
          ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
          ssl_prefer_server_ciphers on;
          access_log /var/log/nginx/access.log;
          error_log /var/log/nginx/error.log;
          gzip on;
          map $http_upgrade $connection_upgrade {
              default upgrade;
              '' close;
          }

          server {
              listen 80;
              #listen [::]:80;            # comment to disable IPv6

              if ($scheme = "http") {
                  return 301 https://$host$request_uri;
              }
              if ($http_x_forwarded_proto = "http") {
                  return 301 https://$host$request_uri;
              }

              listen 443 ssl http2;      # for nginx versions below v1.25.1
              #listen [::]:443 ssl http2; # for nginx versions below v1.25.1 - comment to disable IPv6

              # listen 443 ssl;      # for nginx v1.25.1+
              # listen [::]:443 ssl; # for nginx v1.25.1+ - keep comment to disable IPv6
              # http2 on;            # uncomment to enable HTTP/2 - supported on nginx v1.25.1+

              # listen 443 quic reuseport;       # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+ - please remove "reuseport" if there is already another quic listener on port 443 with enabled reuseport
              # listen [::]:443 quic reuseport;  # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+ - please remove "reuseport" if there is already another quic listener on port 443 with enabled reuseport - keep comment to disable IPv6
              # http3 on;                                 # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+
              # quic_gso on;                              # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+
              # quic_retry on;                            # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+
              # quic_bpf on;                              # improves  HTTP/3 / QUIC - supported on nginx v1.25.0+, if nginx runs as a docker container you need to give it privileged permission to use this option
              # add_header Alt-Svc 'h3=":443"; ma=86400'; # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+

              proxy_buffering off;
              proxy_request_buffering off;

              client_max_body_size 0;
              client_body_buffer_size 512k;
              # http3_stream_buffer_size 512k; # uncomment to enable HTTP/3 / QUIC - supported on nginx v1.25.0+
              proxy_read_timeout 86400s;

              server_name {{ pillar["nextcloud-aio"]["domain"] }};

              location / {
                  proxy_pass http://127.0.0.1:11000$request_uri; # Adjust to match APACHE_PORT and APACHE_IP_BINDING. See https://github.com/nextcloud/all-in-one/blob/main/reverse-proxy.md#adapting-the-sample-web-server-configurations-below

                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Port $server_port;
                  proxy_set_header X-Forwarded-Scheme $scheme;
                  proxy_set_header X-Forwarded-Proto $scheme;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header Host $host;
                  proxy_set_header Early-Data $ssl_early_data;

                  # Websocket
                  proxy_http_version 1.1;
                  proxy_set_header Upgrade $http_upgrade;
                  proxy_set_header Connection $connection_upgrade;
              }

              # If running nginx on a subdomain (eg. nextcloud.example.com) of a domain that already has an wildcard ssl certificate from certbot on this machine,
              # the {{ pillar["nextcloud-aio"]["domain"] }} in the below lines should be replaced with just the domain (eg. example.com), not the subdomain.
              # In this case the subdomain should already be secured without additional actions
              ssl_certificate /opt/acme/cert/nextcloud-aio_{{ pillar["nextcloud-aio"]["domain"] }}_fullchain.cer;   # managed by certbot on host machine
              ssl_certificate_key /opt/acme/cert/nextcloud-aio_{{ pillar["nextcloud-aio"]["domain"] }}_key.key; # managed by certbot on host machine

              ssl_dhparam /etc/dhparam; # curl -L https://ssl-config.mozilla.org/ffdhe2048.txt -o /etc/dhparam

              ssl_early_data on;
              ssl_session_timeout 1d;
              ssl_session_cache shared:SSL:10m;

              ssl_protocols TLSv1.2 TLSv1.3;
              ssl_ecdh_curve x25519:x448:secp521r1:secp384r1:secp256r1;

              ssl_prefer_server_ciphers on;
              #ssl_conf_command Options PrioritizeChaCha;
              ssl_ciphers TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-GCM-SHA256;
          }
        }
  {%- endif %}

download_dhparam:
  file.managed:
    - name: /etc/dhparam
    - source: https://ssl-config.mozilla.org/ffdhe2048.txt
    - skip_verify: True
    - makedirs: True
    - replace: True

  {{ verify_and_issue(acme, "nextcloud-aio", pillar["nextcloud-aio"]["domain"]) }}

nextcloud-aio_data_dirs:
  file.directory:
    - names:
      - /opt/nextcloud-aio/data
    - makedirs: True

# https://github.com/nextcloud/all-in-one/blob/main/compose.yaml
download_docker-compose_file:
  file.managed:
    - name: /opt/nextcloud-aio/docker-compose.yml
    - contents: |
        services:
          nextcloud-aio-mastercontainer:
            image: nextcloud/all-in-one:{{ pillar["nextcloud-aio"]["tag"] }}
            init: true
            restart: always
            container_name: nextcloud-aio-mastercontainer # This line is not allowed to be changed as otherwise AIO will not work correctly
            volumes:
              - nextcloud_aio_mastercontainer:/mnt/docker-aio-config # This line is not allowed to be changed as otherwise the built-in backup solution will not work
              - /var/run/docker.sock:/var/run/docker.sock:ro # May be changed on macOS, Windows or docker rootless. See the applicable documentation. If adjusting, don't forget to also set 'WATCHTOWER_DOCKER_SOCKET_PATH'!
            network_mode: bridge # add to the same network as docker run would do
            ports:
              # - 80:80 # Can be removed when running behind a web server or reverse proxy (like Apache, Nginx, Caddy, Cloudflare Tunnel and else). See https://github.com/nextcloud/all-in-one/blob/main/reverse-proxy.md
              - 8080:8080
              # - 8443:8443 # Can be removed when running behind a web server or reverse proxy (like Apache, Nginx, Caddy, Cloudflare Tunnel and else). See https://github.com/nextcloud/all-in-one/blob/main/reverse-proxy.md
            environment: # Is needed when using any of the options below
              # AIO_DISABLE_BACKUP_SECTION: false # Setting this to true allows to hide the backup section in the AIO interface. See https://github.com/nextcloud/all-in-one#how-to-disable-the-backup-section
              # AIO_COMMUNITY_CONTAINERS: # With this variable, you can add community containers very easily. See https://github.com/nextcloud/all-in-one/tree/main/community-containers#community-containers
              APACHE_PORT: 11000 # Is needed when running behind a web server or reverse proxy (like Apache, Nginx, Caddy, Cloudflare Tunnel and else). See https://github.com/nextcloud/all-in-one/blob/main/reverse-proxy.md
              APACHE_IP_BINDING: 127.0.0.1 # Should be set when running behind a web server or reverse proxy (like Apache, Nginx, Caddy, Cloudflare Tunnel and else) that is running on the same host. See https://github.com/nextcloud/all-in-one/blob/main/reverse-proxy.md
              APACHE_ADDITIONAL_NETWORK: "" # (Optional) Connect the apache container to an additional docker network. Needed when behind a web server or reverse proxy (like Apache, Nginx, Caddy, Cloudflare Tunnel and else) running in a different docker network on same server. See https://github.com/nextcloud/all-in-one/blob/main/reverse-proxy.md
              # BORG_RETENTION_POLICY: --keep-within=7d --keep-weekly=4 --keep-monthly=6 # Allows to adjust borgs retention policy. See https://github.com/nextcloud/all-in-one#how-to-adjust-borgs-retention-policy
              # COLLABORA_SECCOMP_DISABLED: false # Setting this to true allows to disable Collabora's Seccomp feature. See https://github.com/nextcloud/all-in-one#how-to-disable-collaboras-seccomp-feature
              NEXTCLOUD_DATADIR: /opt/nextcloud-aio/data # Allows to set the host directory for Nextcloud's datadir. ⚠️⚠️⚠️ Warning: do not set or adjust this value after the initial Nextcloud installation is done! See https://github.com/nextcloud/all-in-one#how-to-change-the-default-location-of-nextclouds-datadir
              # NEXTCLOUD_MOUNT: /mnt/ # Allows the Nextcloud container to access the chosen directory on the host. See https://github.com/nextcloud/all-in-one#how-to-allow-the-nextcloud-container-to-access-directories-on-the-host
              # NEXTCLOUD_UPLOAD_LIMIT: 16G # Can be adjusted if you need more. See https://github.com/nextcloud/all-in-one#how-to-adjust-the-upload-limit-for-nextcloud
              # NEXTCLOUD_MAX_TIME: 3600 # Can be adjusted if you need more. See https://github.com/nextcloud/all-in-one#how-to-adjust-the-max-execution-time-for-nextcloud
              # NEXTCLOUD_MEMORY_LIMIT: 512M # Can be adjusted if you need more. See https://github.com/nextcloud/all-in-one#how-to-adjust-the-php-memory-limit-for-nextcloud
              # NEXTCLOUD_TRUSTED_CACERTS_DIR: /path/to/my/cacerts # CA certificates in this directory will be trusted by the OS of the nextcloud container (Useful e.g. for LDAPS) See https://github.com/nextcloud/all-in-one#how-to-trust-user-defined-certification-authorities-ca
              # NEXTCLOUD_STARTUP_APPS: deck twofactor_totp tasks calendar contacts notes # Allows to modify the Nextcloud apps that are installed on starting AIO the first time. See https://github.com/nextcloud/all-in-one#how-to-change-the-nextcloud-apps-that-are-installed-on-the-first-startup
              # NEXTCLOUD_ADDITIONAL_APKS: imagemagick # This allows to add additional packages to the Nextcloud container permanently. Default is imagemagick but can be overwritten by modifying this value. See https://github.com/nextcloud/all-in-one#how-to-add-os-packages-permanently-to-the-nextcloud-container
              # NEXTCLOUD_ADDITIONAL_PHP_EXTENSIONS: imagick # This allows to add additional php extensions to the Nextcloud container permanently. Default is imagick but can be overwritten by modifying this value. See https://github.com/nextcloud/all-in-one#how-to-add-php-extensions-permanently-to-the-nextcloud-container
              # NEXTCLOUD_ENABLE_DRI_DEVICE: true # This allows to enable the /dev/dri device for containers that profit from it. ⚠️⚠️⚠️ Warning: this only works if the '/dev/dri' device is present on the host! If it should not exist on your host, don't set this to true as otherwise the Nextcloud container will fail to start! See https://github.com/nextcloud/all-in-one#how-to-enable-hardware-acceleration-for-nextcloud
              # NEXTCLOUD_ENABLE_NVIDIA_GPU: true # This allows to enable the NVIDIA runtime and GPU access for containers that profit from it. ⚠️⚠️⚠️ Warning: this only works if an NVIDIA gpu is installed on the server. See https://github.com/nextcloud/all-in-one#how-to-enable-hardware-acceleration-for-nextcloud.
              NEXTCLOUD_KEEP_DISABLED_APPS: {{ pillar["nextcloud-aio"]["NEXTCLOUD_KEEP_DISABLED_APPS"] | default('false') }} # Setting this to true will keep Nextcloud apps that are disabled in the AIO interface and not uninstall them if they should be installed. See https://github.com/nextcloud/all-in-one#how-to-keep-disabled-apps
              SKIP_DOMAIN_VALIDATION: false # This should only be set to true if things are correctly configured. See https://github.com/nextcloud/all-in-one?tab=readme-ov-file#how-to-skip-the-domain-validation
              # TALK_PORT: 3478 # This allows to adjust the port that the talk container is using which is exposed on the host. See https://github.com/nextcloud/all-in-one#how-to-adjust-the-talk-port
              # WATCHTOWER_DOCKER_SOCKET_PATH: /var/run/docker.sock # Needs to be specified if the docker socket on the host is not located in the default '/var/run/docker.sock'. Otherwise mastercontainer updates will fail. For macos it needs to be '/var/run/docker.sock'
            # security_opt: ["label:disable"] # Is needed when using SELinux

        #   # Optional: Caddy reverse proxy. See https://github.com/nextcloud/all-in-one/discussions/575
        #   # Hint: You need to uncomment APACHE_PORT: 11000 above, adjust cloud.example.com to your domain and uncomment the necessary docker volumes at the bottom of this file in order to make it work
        #   # You can find further examples here: https://github.com/nextcloud/all-in-one/discussions/588
        #   caddy:
        #     image: caddy:alpine
        #     restart: always
        #     container_name: caddy
        #     volumes:
        #       - caddy_certs:/certs
        #       - caddy_config:/config
        #       - caddy_data:/data
        #       - caddy_sites:/srv
        #     network_mode: "host"
        #     configs:
        #       - source: Caddyfile
        #         target: /etc/caddy/Caddyfile
        # configs:
        #   Caddyfile:
        #     content: |
        #       # Adjust cloud.example.com to your domain below
        #       https://cloud.example.com:443 {
        #         reverse_proxy localhost:11000
        #       }

        volumes: # If you want to store the data on a different drive, see https://github.com/nextcloud/all-in-one#how-to-store-the-filesinstallation-on-a-separate-drive
          nextcloud_aio_mastercontainer:
            name: nextcloud_aio_mastercontainer # This line is not allowed to be changed as otherwise the built-in backup solution will not work
          # caddy_certs:
          # caddy_config:
          # caddy_data:
          # caddy_sites:

docker_compose_up:
  cmd.run:
    - name: docker-compose -f /opt/nextcloud-aio/docker-compose.yml up -d
    - cwd: /opt/nextcloud-aio

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


