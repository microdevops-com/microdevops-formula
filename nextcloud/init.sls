{% if pillar["nextcloud"] is defined and pillar["acme"] is defined %}
{% set acme = pillar['acme'].keys() | first %}
  {% if pillar["docker-ce"] is not defined %}

docker_install_00:
  file.directory:
    - name: /etc/docker
    - mode: 700

docker_install_01:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: |
        { "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }

docker_install_1:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/{{ grains["os"]|lower }} {{ grains["oscodename"] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/{{ grains["os"]|lower }}/gpg

docker_install_2:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs: 
        - docker-ce: "{{ pillar["nextcloud"]["docker-ce_version"] }}*"
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
  {%- endif %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

  {%- if pillar["nextcloud"]["nginx_sites_enabled"] | default(false) %}
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
    {%- for domain in pillar["nextcloud"]["domains"] %}
create /etc/nginx/sites-available/{{ domain["name"] }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ domain["name"] }}.conf
    - contents: |
        map $http_upgrade $connection_upgrade {
          default upgrade;
          ''      close;
        }
        {%- if pillar["nextcloud"]["external_port"] is not defined %}
        server {
          listen 80;
          server_name {{ domain["name"] }};
          return 301 https://$host$request_uri;
        }
        {%- endif %}
            upstream {{ domain["name"] | replace(".","_") }} {
                server localhost:{{ domain["internal_port"] }};
            }
            
            server {
                listen 443 ssl;
                
                server_name {{ domain["name"] }};
                root /opt/nextcloud/{{ domain["name"] }}/data;
                ssl_certificate /opt/acme/cert/nextcloud_{{ domain["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/nextcloud_{{ domain["name"] }}_key.key;
                
                fastcgi_read_timeout 300s;
                
                # Add headers to serve security related headers
                # Before enabling Strict-Transport-Security headers please read into this
                # topic first.
                add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
                
                # WARNING: Only add the preload option once you read about
                # the consequences in https://hstspreload.org/. This option
                # will add the domain to a hardcoded list that is shipped
                # in all major browsers and getting removed from this list
                # could take several months.
                add_header Referrer-Policy "no-referrer" always;
                add_header X-Content-Type-Options "nosniff" always;
                add_header X-Download-Options "noopen" always;
                add_header X-Frame-Options "SAMEORIGIN" always;
                add_header X-Permitted-Cross-Domain-Policies "none" always;
                add_header X-Robots-Tag "noindex, nofollow" always;
                add_header X-XSS-Protection "1; mode=block" always;

                # Remove X-Powered-By, which is an information leak
                fastcgi_hide_header X-Powered-By;
                
                location = /robots.txt {
                    allow all;
                    log_not_found off;
                    access_log off;
                }
                
                # The following 2 rules are only needed for the user_webfinger app.
                # Uncomment it if you're planning to use this app.
                #rewrite ^/.well-known/host-meta /public.php?service=host-meta last;
                #rewrite ^/.well-known/host-meta.json /public.php?service=host-meta-json last;
                #
                # The following rule is only needed for the Social app.
                # Uncomment it if you're planning to use this app.
                #rewrite ^/.well-known/webfinger /public.php?service=webfinger last;
                #
                # The folliwing 2 rules have been added to remove the following warnings from the status page:
                #    "Your web server is not properly set up to resolve "/.well-known/webfinger".
                #     Further information can be found in the documentation."
                #    "Your web server is not properly set up to resolve "/.well-known/nodeinfo".
                #     Further information can be found in the documentation."
                rewrite ^/.well-known/webfinger /index.php$uri redirect;
                rewrite ^/.well-known/nodeinfo /index.php$uri redirect;


                location = /.well-known/carddav {
                    return 301 $scheme://$host/remote.php/dav;
                }

                location = /.well-known/caldav {
                    return 301 $scheme://$host/remote.php/dav;
                }

                # set max upload size
                client_max_body_size 10G;
                fastcgi_buffers 64 4K;

                # Enable gzip but do not remove ETag headers
                gzip on;
                gzip_vary on;
                gzip_comp_level 4;
                gzip_min_length 256;
                gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
                gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

                # Uncomment if your server is build with the ngx_pagespeed module
                # This module is currently not supported.
                #pagespeed off;

                location / {
                    rewrite ^ /index.php;
                }

                location ~ ^\/(?:build|tests|config|lib|3rdparty|templates|data)\/ {
                    deny all;
                }
                location ~ ^\/(?:\.|autotest|occ|issue|indie|db_|console) {
                    deny all;
                }

                location ~ ^\/(?:index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|oc[ms]-provider\/.+)\.php(?:$|\/) {
                    fastcgi_split_path_info ^(.+?\.php)(\/.*|)$;
                    set $path_info $fastcgi_path_info;
                    try_files $fastcgi_script_name =404;
                    include fastcgi_params;
                    fastcgi_param SCRIPT_FILENAME /var/www/html/$fastcgi_script_name;
                    fastcgi_param PATH_INFO $path_info;
                    fastcgi_param HTTPS on;

                    # Avoid sending the security headers twice
                    fastcgi_param modHeadersAvailable true;

                    # Enable pretty urls
                    fastcgi_param front_controller_active true;
                    fastcgi_pass {{ domain["name"] | replace(".","_") }};
                    fastcgi_intercept_errors on;
                    fastcgi_request_buffering off;
                }

                location ~ ^\/(?:updater|oc[ms]-provider)(?:$|\/) {
                    try_files $uri/ =404;
                    index index.php;
                }

                # Adding the cache control header for js, css and map files
                # Make sure it is BELOW the PHP block
                location ~ \.(?:css|js|woff2?|svg|gif|map)$ {
                    try_files $uri /index.php$request_uri;
                    add_header Cache-Control "public, max-age=15778463";
                    # Add headers to serve security related headers (It is intended to
                    # have those duplicated to the ones above)
                    # Before enabling Strict-Transport-Security headers please read into
                    # this topic first.
                    #add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
                    #
                    # WARNING: Only add the preload option once you read about
                    # the consequences in https://hstspreload.org/. This option
                    # will add the domain to a hardcoded list that is shipped
                    # in all major browsers and getting removed from this list
                    # could take several months.
                    add_header Referrer-Policy "no-referrer" always;
                    add_header X-Content-Type-Options "nosniff" always;
                    add_header X-Download-Options "noopen" always;
                    add_header X-Frame-Options "SAMEORIGIN" always;
                    add_header X-Permitted-Cross-Domain-Policies "none" always;
                    add_header X-Robots-Tag "noindex, nofollow" always;
                    add_header X-XSS-Protection "1; mode=block" always;

                    # Optional: Don't log access to assets
                    access_log off;
                }

                location ~ \.(?:png|html|ttf|ico|jpg|jpeg|bcmap|mp4|webm)$ {
                    try_files $uri /index.php$request_uri;
                    # Optional: Don't log access to other assets
                    access_log off;
                }
            }
create symlink /etc/nginx/sites-enabled/{{ domain["name"] }}.conf:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ domain["name"] }}.conf
    - target: /etc/nginx/sites-available/{{ domain["name"] }}.conf
    - force: True
    {%- endfor %}
  
  {%- else %}

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
            include /etc/nginx/mime.types;
            default_type application/octet-stream;
            sendfile on;
            keepalive_timeout 65;

            server {
                listen 80;
                return 301 https://$host$request_uri;
            }
    {%- for domain in pillar["nextcloud"]["domains"] %}
            
            upstream {{ domain["name"] | replace(".","_") }} {
                server localhost:{{ domain["internal_port"] }};
            }
            
            server {
                listen 443 ssl;
                
                server_name {{ domain["name"] }};
                root /opt/nextcloud/{{ domain["name"] }}/data;
                ssl_certificate /opt/acme/cert/nextcloud_{{ domain["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/nextcloud_{{ domain["name"] }}_key.key;
                
                fastcgi_read_timeout 300s;
                
                # Add headers to serve security related headers
                # Before enabling Strict-Transport-Security headers please read into this
                # topic first.
                add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
                
                # WARNING: Only add the preload option once you read about
                # the consequences in https://hstspreload.org/. This option
                # will add the domain to a hardcoded list that is shipped
                # in all major browsers and getting removed from this list
                # could take several months.
                add_header Referrer-Policy "no-referrer" always;
                add_header X-Content-Type-Options "nosniff" always;
                add_header X-Download-Options "noopen" always;
                add_header X-Frame-Options "SAMEORIGIN" always;
                add_header X-Permitted-Cross-Domain-Policies "none" always;
                add_header X-Robots-Tag "noindex, nofollow" always;
                add_header X-XSS-Protection "1; mode=block" always;

                # Remove X-Powered-By, which is an information leak
                fastcgi_hide_header X-Powered-By;
                
                location = /robots.txt {
                    allow all;
                    log_not_found off;
                    access_log off;
                }
                
                # The following 2 rules are only needed for the user_webfinger app.
                # Uncomment it if you're planning to use this app.
                #rewrite ^/.well-known/host-meta /public.php?service=host-meta last;
                #rewrite ^/.well-known/host-meta.json /public.php?service=host-meta-json last;
                #
                # The following rule is only needed for the Social app.
                # Uncomment it if you're planning to use this app.
                #rewrite ^/.well-known/webfinger /public.php?service=webfinger last;
                #
                # The folliwing 2 rules have been added to remove the following warnings from the status page:
                #    "Your web server is not properly set up to resolve "/.well-known/webfinger".
                #     Further information can be found in the documentation."
                #    "Your web server is not properly set up to resolve "/.well-known/nodeinfo".
                #     Further information can be found in the documentation."
                rewrite ^/.well-known/webfinger /index.php$uri redirect;
                rewrite ^/.well-known/nodeinfo /index.php$uri redirect;


                location = /.well-known/carddav {
                    return 301 $scheme://$host/remote.php/dav;
                }

                location = /.well-known/caldav {
                    return 301 $scheme://$host/remote.php/dav;
                }

                # set max upload size
                client_max_body_size 10G;
                fastcgi_buffers 64 4K;

                # Enable gzip but do not remove ETag headers
                gzip on;
                gzip_vary on;
                gzip_comp_level 4;
                gzip_min_length 256;
                gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
                gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

                # Uncomment if your server is build with the ngx_pagespeed module
                # This module is currently not supported.
                #pagespeed off;

                location / {
                    rewrite ^ /index.php;
                }

                location ~ ^\/(?:build|tests|config|lib|3rdparty|templates|data)\/ {
                    deny all;
                }
                location ~ ^\/(?:\.|autotest|occ|issue|indie|db_|console) {
                    deny all;
                }

                location ~ ^\/(?:index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|oc[ms]-provider\/.+)\.php(?:$|\/) {
                    fastcgi_split_path_info ^(.+?\.php)(\/.*|)$;
                    set $path_info $fastcgi_path_info;
                    try_files $fastcgi_script_name =404;
                    include fastcgi_params;
                    fastcgi_param SCRIPT_FILENAME /var/www/html/$fastcgi_script_name;
                    fastcgi_param PATH_INFO $path_info;
                    fastcgi_param HTTPS on;

                    # Avoid sending the security headers twice
                    fastcgi_param modHeadersAvailable true;

                    # Enable pretty urls
                    fastcgi_param front_controller_active true;
                    fastcgi_pass {{ domain["name"] | replace(".","_") }};
                    fastcgi_intercept_errors on;
                    fastcgi_request_buffering off;
                }

                location ~ ^\/(?:updater|oc[ms]-provider)(?:$|\/) {
                    try_files $uri/ =404;
                    index index.php;
                }

                # Adding the cache control header for js, css and map files
                # Make sure it is BELOW the PHP block
                location ~ \.(?:css|js|woff2?|svg|gif|map)$ {
                    try_files $uri /index.php$request_uri;
                    add_header Cache-Control "public, max-age=15778463";
                    # Add headers to serve security related headers (It is intended to
                    # have those duplicated to the ones above)
                    # Before enabling Strict-Transport-Security headers please read into
                    # this topic first.
                    #add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
                    #
                    # WARNING: Only add the preload option once you read about
                    # the consequences in https://hstspreload.org/. This option
                    # will add the domain to a hardcoded list that is shipped
                    # in all major browsers and getting removed from this list
                    # could take several months.
                    add_header Referrer-Policy "no-referrer" always;
                    add_header X-Content-Type-Options "nosniff" always;
                    add_header X-Download-Options "noopen" always;
                    add_header X-Frame-Options "SAMEORIGIN" always;
                    add_header X-Permitted-Cross-Domain-Policies "none" always;
                    add_header X-Robots-Tag "noindex, nofollow" always;
                    add_header X-XSS-Protection "1; mode=block" always;

                    # Optional: Don't log access to assets
                    access_log off;
                }

                location ~ \.(?:png|html|ttf|ico|jpg|jpeg|bcmap|mp4|webm)$ {
                    try_files $uri /index.php$request_uri;
                    # Optional: Don't log access to other assets
                    access_log off;
                }
            }
    {%- endfor %}
        }
  {%- endif%}
nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["nextcloud"]["domains"] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme }}/verify_and_issue.sh nextcloud {{ domain["name"] }}"

nextcloud_data_dir_{{ loop.index }}:
  file.directory:
    - name: /opt/nextcloud/{{ domain["name"] }}/data
    - mode: 755
    - makedirs: True

nextcloud_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["image"] }}

nextcloud_container_{{ loop.index }}:
  docker_container.running:
    - name: nextcloud-{{ domain["name"] }}
    - user: root
    - image: {{ domain["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:{{ domain["internal_port"] }}:9000/tcp
    - binds:
        - /opt/nextcloud/{{ domain["name"] }}/data:/var/www/html:rw
    - environment:
    {%- for var_key, var_val in domain["env_vars"].items() %}
        - {{ var_key }}: {{ var_val }}
    {%- endfor %}

nextcloud-available_{{ loop.index }}:
  cmd.run:
    - name: 'while [ $(curl -sL -u {{ domain["env_vars"]["NEXTCLOUD_ADMIN_USER"] }}:{{ domain["env_vars"]["NEXTCLOUD_ADMIN_PASSWORD"] }} https://{{ domain["name"] }}/ocs/v2.php/apps/serverinfo/api/v1/info?format=json | jq -r ".ocs.meta.statuscode") != 200 ]; do sleep 1; done'
    - timeout: 120

    {% if "php_fpm" in domain and "pm.max_children" in domain["php_fpm"] %}
nextcloud_php-fpm_set_pm.max_children_{{ loop.index }}:
  cmd.run:
    - name: docker exec nextcloud-{{ domain["name"] }} bash -c "sed -Ei  's/^ *pm\.max_children\ =.*$/pm.max_children = {{ domain["php_fpm"]["pm.max_children"] }}/g' /usr/local/etc/php-fpm.d/www.conf"
    {% endif %}
nextcloud_container_install_libmagickcore_{{ loop.index }}:
  cmd.run:
    - name: docker exec nextcloud-{{ domain["name"] }} bash -c 'apt update && apt install libmagickcore-6.q16-6-extra iproute2 -y'

nextcloud_config_default_phone_region_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'sleep 10; php occ config:system:set default_phone_region --value="{{ domain["default_phone_region"] }}"'

nextcloud_config_overwrite_cli_url_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php /var/www/html/occ --no-warnings config:system:set overwrite.cli.url --value="{{ domain["overwrite_cli_url"] }}"'

nextcloud_missing_indexes_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php /var/www/html/occ db:add-missing-indices'

nextcloud_cron_{{ loop.index }}:
  cron.present:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} php -f /var/www/html/cron.php
    - identifier: nextcloud-cron-{{ domain["name"] }}
    - user: root
    - minute: "*/5"

nextcloud_update_all_applications_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:update --all; sleep 10'

    {%- if "onlyoffice" in domain %}
nextcloud_config_onlyoffice_0_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:disable richdocuments || true'

nextcloud_config_onlyoffice_1_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:install onlyoffice || true'

nextcloud_config_onlyoffice_1_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:enable onlyoffice --force || true'

nextcloud_config_onlyoffice_2_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:system:set onlyoffice DocumentServerUrl --value={{ domain["onlyoffice"]["DocumentServerUrl"] }}'

nextcloud_config_onlyoffice_3_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:system:set onlyoffice DocumentServerInternalUrl --value={{ domain["onlyoffice"]["DocumentServerInternalUrl"] }}'

nextcloud_config_onlyoffice_4_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:system:set onlyoffice StorageUrl --value={{ domain["onlyoffice"]["StorageUrl"] }}'

    {%- endif %}
    {%- if "collabora" in domain %}
nextcloud_config_collabora_0_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:disable onlyoffice || true'

nextcloud_config_collabora_1_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:install richdocuments || true'

nextcloud_config_collabora_2_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:enable --force richdocuments || true'

nextcloud_config_collabora_3_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:app:set richdocuments wopi_url --value {{ domain["collabora"]["DocumentServerUrl"] }}'

nextcloud_config_collabora_4_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:app:set richdocuments wopi_allowlist --value {{ domain["collabora"]["wopi_allowlist"] }}'

      {%- if "doc_format" in domain["collabora"] %}
nextcloud_config_collabora_5_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:app:set richdocuments doc_format --value {{ domain["collabora"]["doc_format"] }}'
      {%- endif %}

nextcloud_config_collabora_6_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ richdocuments:activate-config'

    {%- endif %}
    {%- if "user_saml" in domain %}

nextcloud_config_user_saml_1_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:install user_saml || true'

nextcloud_config_user_saml_2_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:enable user_saml'

nextcloud_config_user_saml_3_{{ loop.index }}:
  file.serialize:
    - name: /opt/nextcloud/{{ domain["name"] }}/data/user_saml_config.json
    - dataset:
        apps:
          user_saml: {{ domain["user_saml"] | json }}
    - formatter: json

nextcloud_config_user_saml_4_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:import < user_saml_config.json'

nextcloud_remove_config_user_saml_{{ loop.index }}:
  file.absent:
    - name: /opt/nextcloud/{{ domain["name"] }}/data/user_saml_config.json

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
